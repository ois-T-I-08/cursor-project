import { describe, expect, it } from "vitest";
import { TeamCandidateGenerator, teamKey } from "@/lib/team-recommendations/candidate-generator";
import { stableHash, simulationCacheKey, teamRecommendationRequestHash } from "@/lib/team-recommendations/cache-key";
import { GcsimConfigGenerator, UnsupportedGcsimInputError } from "@/lib/team-recommendations/config-generator";
import { GcsimArtifactMapper, GcsimCharacterMapper, GcsimWeaponMapper } from "@/lib/team-recommendations/mappers";
import { GcsimOutputParser } from "@/lib/team-recommendations/output-parser";
import { parseTeamRecommendationRequest } from "@/lib/team-recommendations/validation";
import { hasRole, isKnownPhysicalAttacker } from "@/lib/team-recommendations/role-profiles";
import gcsimFixture from "./fixtures/gcsim-result-v2.43.4.json";
import type { TeamCandidate, TeamRecommendationRequest } from "@/lib/team-recommendations/types";

const request: TeamRecommendationRequest = {
  attackerId: "10000089", mode: "spiralAbyss", half: "upper", ownedOnly: true, enemy: "single", preference: "damage",
  characters: [
    build("10000089", "hydro", "11513", "15032"),
    build("10000087", "hydro", "14514", "15031"),
    build("10000025", "hydro", "11401"),
    build("10000054", "hydro", "14401"),
    build("10000032", "pyro", "11401"),
  ],
};
const candidate: TeamCandidate = {
  attackerId: "10000089", members: ["10000089", "10000087", "10000025", "10000054"], sourceTypes: ["aza"], observedByAza: true,
  azaUsageRate: 0.08, reactionType: "mono", hasSustain: true, energyStability: 0.8, rotationConfidence: "medium",
};

describe("gcsim ID mappers", () => {
  it("maps official character, weapon and artifact IDs", () => {
    expect(new GcsimCharacterMapper().map("10000087")).toBe("neuvillette");
    expect(new GcsimWeaponMapper().map("14514")).toBe("tomeoftheeternalflow");
    expect(new GcsimArtifactMapper().map("15031")).toBe("marechausseehunter");
  });
  it("returns null for unsupported IDs", () => {
    expect(new GcsimCharacterMapper().map("99999999")).toBeNull();
    expect(new GcsimWeaponMapper().map("99999")).toBeNull();
    expect(new GcsimArtifactMapper().map("99999")).toBeNull();
  });
});

describe("trusted config generator", () => {
  it("generates a stable server-owned config", () => {
    const result = new GcsimConfigGenerator().generate({ candidate, builds: request.characters, iterations: 1000, durationSeconds: 90, enemy: "single" });
    expect(result.config).toMatchSnapshot();
    expect(result.config).toContain('furina add weapon="splendoroftranquilwaters"');
    expect(result.config).toContain("target lvl=100 resist=0.1");
    expect(result.config).toContain("while 1 {");
  });
  it("rejects unsupported mappings instead of guessing", () => {
    const changed = request.characters.map((value) => value.characterId === "10000089" ? { ...value, weapon: { ...value.weapon!, weaponId: "99999" } } : value);
    expect(() => new GcsimConfigGenerator().generate({ candidate, builds: changed, iterations: 1000, durationSeconds: 90, enemy: "single" }))
      .toThrow(UnsupportedGcsimInputError);
  });
  it("rejects unsupported characters and artifacts independently", () => {
    const unknownCharacter = { ...candidate, members: ["99999999", ...candidate.members.slice(1)] };
    const unknownBuilds = [build("99999999", "hydro", "11513"), ...request.characters.slice(1)];
    expect(() => new GcsimConfigGenerator().generate({ candidate: unknownCharacter, builds: unknownBuilds, iterations: 1000, durationSeconds: 90, enemy: "single" }))
      .toThrow("unsupportedCharacter");
    const unknownArtifact = request.characters.map((value) => value.characterId === "10000089"
      ? { ...value, artifacts: { sets: [{ setId: "99999", count: 4 }], stats: {} } }
      : value);
    expect(() => new GcsimConfigGenerator().generate({ candidate, builds: unknownArtifact, iterations: 1000, durationSeconds: 90, enemy: "single" }))
      .toThrow("unsupportedArtifact");
  });
});

describe("request boundary", () => {
  it("accepts normalized fighting data and no account identifiers", () => {
    const parsed = parseTeamRecommendationRequest(request);
    expect(parsed.attackerId).toBe("10000089");
    expect(JSON.stringify(parsed)).not.toMatch(/cookie|uid|account/i);
  });
  it.each(["config", "command", "path", "cookie", "uid"])("rejects arbitrary %s", (field) => {
    expect(() => parseTeamRecommendationRequest({ ...request, [field]: "malicious" })).toThrow("invalidRequest");
  });
  it("handles partially missing optional build fields", () => {
    const partial = { ...request, characters: request.characters.map((value) => value.characterId === "10000025" ? { ...value, talents: undefined, weapon: undefined, artifacts: undefined, inputQuality: "partial" } : value) };
    expect(parseTeamRecommendationRequest(partial).characters[2].inputQuality).toBe("partial");
  });
});

describe("candidate and cache normalization", () => {
  it("uses small role profiles instead of fixed team registrations", () => {
    expect(hasRole("10000032", "buffer", "healer", "battery")).toBe(true);
    expect(isKnownPhysicalAttacker("10000051")).toBe(true);
  });
  it("deduplicates the same partner set while keeping attacker first", () => {
    expect(teamKey("10000089", candidate.members)).toBe(teamKey("10000089", ["10000054", "10000089", "10000025", "10000087"]));
  });
  it("generates an AZA candidate and tolerates no AZA data", () => {
    const generator = new TeamCandidateGenerator();
    const aza = generator.generate({ request, abyssTeams: [{ half: "upper", members: candidate.members, usageRate: 0.1, ownershipRate: 0.2, usageAmongOwnersRate: 0.5 }] });
    expect(aza[0].sourceTypes).toContain("aza");
    expect(generator.generate({ request, abyssTeams: [] }).length).toBeGreaterThan(0);
  });
  it("creates stable canonical hashes", () => {
    expect(stableHash({ b: 2, a: 1 })).toBe(stableHash({ a: 1, b: 2 }));
    const key = simulationCacheKey({ request, candidate, iterations: 1000, durationSeconds: 90 });
    expect(key).toHaveLength(64);
    expect(simulationCacheKey({ request, candidate, iterations: 1000, durationSeconds: 60 })).not.toBe(key);
    const reordered = { ...request, characters: [...request.characters].reverse() };
    expect(teamRecommendationRequestHash(reordered)).toBe(teamRecommendationRequestHash(request));
    expect(simulationCacheKey({ request: reordered, candidate, iterations: 1000, durationSeconds: 90 })).toBe(key);
  });
});

describe("gcsim output parser", () => {
  it("normalizes DPS, reactions and energy", () => {
    const result = new GcsimOutputParser().parse(JSON.stringify(gcsimFixture));
    expect(result).toEqual({ estimatedDps: 78543.2, iterations: 1000, reactions: { vaporize: 12.5 }, endingEnergy: [45] });
  });
  it.each(["not json", "{}", '{"schema_version":{"major":"3","minor":"0"},"statistics":{"iterations":1000,"dps":{"mean":1}}}'])("rejects invalid output", (raw) => {
    expect(() => new GcsimOutputParser().parse(raw)).toThrow("invalidGcsimOutput");
  });
  it("rejects output from a different gcsim commit", () => {
    expect(() => new GcsimOutputParser().parse(JSON.stringify({ ...gcsimFixture, sim_version: "wrong-commit" })))
      .toThrow("invalidGcsimOutput");
  });
});

function build(characterId: string, element: TeamRecommendationRequest["characters"][number]["element"], weaponId: string, setId?: string) {
  return {
    characterId, element, rarity: 5 as const, isOwned: true, level: 90, ascension: 6, constellation: 0,
    talents: { normal: 9, skill: 9, burst: 9 }, weapon: { weaponId, level: 90, ascension: 6, refinement: 1 },
    artifacts: { sets: setId ? [{ setId, count: 4 }] : [], stats: { hpFlat: 4780, critRate: 31.1, critDamage: 62.2 } },
    inputQuality: "exact" as const, defaultedFields: [],
  };
}
