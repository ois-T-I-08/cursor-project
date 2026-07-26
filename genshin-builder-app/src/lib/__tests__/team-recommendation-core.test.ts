import { describe, expect, it } from "vitest";
import { TeamCandidateGenerator, teamKey } from "@/lib/team-recommendations/candidate-generator";
import { stableHash, teamRecommendationRequestHash } from "@/lib/team-recommendations/cache-key";
import { parseTeamRecommendationRequest } from "@/lib/team-recommendations/validation";
import { hasRole, isKnownPhysicalAttacker } from "@/lib/team-recommendations/role-profiles";
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
    const partial = {
      ...request,
      characters: request.characters.map((value) =>
        value.characterId === "10000025"
          ? { ...value, talents: undefined, weapon: undefined, artifacts: undefined, inputQuality: "partial" as const }
          : value),
    };
    expect(parseTeamRecommendationRequest(partial).characters[2].inputQuality).toBe("partial");
  });
});

describe("candidate normalization", () => {
  it("uses small role profiles instead of fixed team registrations", () => {
    expect(hasRole("10000032", "buffer", "healer", "battery")).toBe(true);
    expect(isKnownPhysicalAttacker("10000051")).toBe(true);
  });
  it("deduplicates the same partner set while keeping attacker first", () => {
    expect(teamKey("10000089", candidate.members)).toBe(teamKey("10000089", ["10000054", "10000089", "10000025", "10000087"]));
  });
  it("generates an AZA candidate and tolerates no AZA data", () => {
    const generator = new TeamCandidateGenerator();
    const aza = generator.generate({
      request,
      abyssTeams: [{ half: "upper", members: candidate.members, usageRate: 0.1, ownershipRate: 0.2, usageAmongOwnersRate: 0.5 }],
    });
    expect(aza[0].sourceTypes).toContain("aza");
    expect(generator.generate({ request, abyssTeams: [] }).length).toBeGreaterThan(0);
  });
  it("creates stable canonical hashes", () => {
    expect(stableHash({ b: 2, a: 1 })).toBe(stableHash({ a: 1, b: 2 }));
    const reordered = { ...request, characters: [...request.characters].reverse() };
    expect(teamRecommendationRequestHash(reordered)).toBe(teamRecommendationRequestHash(request));
  });
});

function build(
  characterId: string,
  element: TeamRecommendationRequest["characters"][number]["element"],
  weaponId: string,
  setId?: string,
) {
  return {
    characterId, element, rarity: 5 as const, isOwned: true, level: 90, ascension: 6, constellation: 0,
    talents: { normal: 9, skill: 9, burst: 9 }, weapon: { weaponId, level: 90, ascension: 6, refinement: 1 },
    artifacts: { sets: setId ? [{ setId, count: 4 }] : [], stats: { hpFlat: 4780, critRate: 31.1, critDamage: 62.2 } },
    inputQuality: "exact" as const, defaultedFields: [],
  };
}
