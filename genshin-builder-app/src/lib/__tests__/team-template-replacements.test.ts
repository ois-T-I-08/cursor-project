import { resolve } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { buildEvaluationInput, prefilterReplacementCandidates } from "../team-recommendations/replacements/candidate-filter";
import { DeepSeekReplacementClient } from "../team-recommendations/replacements/deepseek-client";
import { validateAndFinalizeReplacement } from "../team-recommendations/replacements/final-validator";
import {
  createTeamHash,
  normalizeCharacterId,
  normalizeExternalRole,
  normalizeImportedTeam,
} from "../team-recommendations/replacements/normalization";
import { replacementCacheKey } from "../team-recommendations/replacements/replacement-cache-key";
import { LocalJsonTeamSource } from "../team-recommendations/replacements/sources";
import type { CharacterTeamProfile, ReplacementResult } from "../team-recommendations/replacements/types";

const team = ["10000089", "10000052", "10000071", "10000058"];
const profiles = [
  profile("10000089", ["main_dps"], ["on_field_dps"], "high", "on_field", "pyro"),
  profile("10000052", ["sub_dps"], ["off_field_dps", "hydro_applier"], "low", "off_field", "hydro"),
  profile("10000071", ["support"], ["buffer", "energy_battery"], "low", "off_field", "anemo"),
  profile("10000058", ["healer"], ["team_healer"], "low", "off_field", "geo", true),
  profile("10000030", ["main_dps"], ["on_field_dps"], "high", "on_field", "pyro"),
  profile("10000031", ["sub_dps"], ["off_field_dps", "hydro_applier"], "low", "off_field", "hydro"),
  profile("10000032", ["support"], ["buffer"], "low", "off_field", "anemo"),
  profile("10000033", ["sub_dps"], ["off_field_dps", "hydro_applier"], "low", "off_field", "hydro"),
];

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("team template normalization", () => {
  it("creates an order-independent team hash while preserving display order", () => {
    expect(createTeamHash(team)).toBe(createTeamHash([...team].reverse()));
    const normalized = normalizeImportedTeam({
      source: "local",
      sourceTeamId: "local-1",
      name: "Test",
      characters: team.map((characterId, slotIndex) => ({
        characterId,
        sourceRole: slotIndex === 0 ? "Main DPS" : "Support",
        slotIndex,
      })),
      fetchedAt: "2026-07-26T00:00:00.000Z",
      dataVersion: "v1",
    });
    expect(normalized.characters.map((member) => member.characterId)).toEqual(team);
  });

  it("normalizes IDs and external roles and rejects malformed IDs", () => {
    expect(normalizeCharacterId(" 10000089 ")).toBe("10000089");
    expect(normalizeExternalRole("Sub-DPS")).toBe("sub_dps");
    expect(normalizeExternalRole("unknown role")).toBe("flex");
    expect(() => normalizeCharacterId("nahida")).toThrow("invalidCharacterId");
  });

  it("loads a bounded local JSON source without a network request", async () => {
    const source = new LocalJsonTeamSource(
      resolve(process.cwd(), "data", "team-templates", "local-source.test.json"),
    );
    const values = await source.fetchTeams();
    expect(values).toHaveLength(1);
    expect(values[0]?.sourceTeamId).toBe("fixture-team");
  });

  it("rejects non-HTTPS and non-allowlisted source URLs", () => {
    vi.stubEnv("TEAM_SOURCE_ALLOWED_HOSTS", "genshin-builds.com");
    const base = {
      source: "local" as const,
      sourceTeamId: "local-url",
      name: "Test",
      characters: team.map((characterId, slotIndex) => ({
        characterId,
        slotIndex,
      })),
      fetchedAt: "2026-07-26T00:00:00.000Z",
      dataVersion: "v1",
    };
    expect(() =>
      normalizeImportedTeam({
        ...base,
        sourceUrl: "https://evil.example/team",
      }),
    ).toThrow("sourceHostNotAllowed");
    expect(() =>
      normalizeImportedTeam({
        ...base,
        sourceUrl: "http://genshin-builds.com/team",
      }),
    ).toThrow("invalidSourceUrl");
  });

  it("rejects source URLs until an allowlist is explicitly configured", () => {
    vi.stubEnv("TEAM_SOURCE_ALLOWED_HOSTS", "");
    expect(() =>
      normalizeImportedTeam({
        source: "local",
        sourceTeamId: "local-url-default-deny",
        name: "Test",
        characters: team.map((characterId, slotIndex) => ({
          characterId,
          slotIndex,
        })),
        sourceUrl: "https://genshin-builds.com/team",
        fetchedAt: "2026-07-26T00:00:00.000Z",
        dataVersion: "v1",
      }),
    ).toThrow("sourceHostNotAllowed");
  });
});

describe("replacement candidate safeguards", () => {
  it("excludes current team members and applies the candidate cap", () => {
    const original = profiles[1]!;
    const candidates = prefilterReplacementCandidates({
      team,
      original,
      remaining: profiles.slice(0, 4).filter((value) => value !== original),
      profiles,
      requiredFunctions: ["hydro_applier"],
      requiredElements: ["hydro"],
      maxCandidates: 2,
    });
    expect(candidates).toHaveLength(2);
    expect(candidates.map((value) => value.profile.characterId)).not.toContain(
      original.characterId,
    );
    expect(candidates.every((value) => !team.includes(value.profile.characterId))).toBe(true);
  });

  it("drops disallowed and duplicate AI candidates and applies field-time penalties", () => {
    const input = buildEvaluationInput({
      gameDataVersion: "game-v1",
      team,
      replacingCharacterId: "10000052",
      teamArchetype: "reaction",
      profiles,
    });
    const allowedId = input.allowedCandidateIds[0]!;
    const raw: ReplacementResult = {
      slotAnalysis: {
        requiredFunctions: [],
        preferredFunctions: [],
        dependencies: [],
        replacementRisks: [],
      },
      candidates: [
        evaluation(allowedId, 95),
        evaluation(allowedId, 90),
        evaluation("10000999", 100),
      ],
    };
    const result = validateAndFinalizeReplacement(
      raw,
      input,
      new Map(profiles.map((value) => [value.characterId, value])),
    );
    expect(result.candidates).toHaveLength(1);
    expect(result.candidates[0]?.finalScore).toBeLessThanOrEqual(95);
    expect(result.candidates[0]?.deterministicPenalty).toBeGreaterThanOrEqual(0);
  });

  it("changes the cache key whenever a required version changes", () => {
    const base = {
      teamHash: "hash",
      replacedCharacterId: "10000052",
      gameDataVersion: "5.0",
      characterDataVersion: "profiles-v1",
      promptVersion: "prompt-v1",
      rulesVersion: "rules-v1",
      modelIdentifier: "deepseek-v4-flash",
    };
    expect(replacementCacheKey(base)).not.toBe(
      replacementCacheKey({ ...base, rulesVersion: "rules-v2" }),
    );
  });
});

describe("DeepSeek JSON mode client", () => {
  it("retries an empty response once and parses a strict JSON result", async () => {
    vi.stubEnv("DEEPSEEK_ENABLED", "true");
    vi.stubEnv("DEEPSEEK_API_KEY", "test-only-secret");
    vi.stubEnv("DEEPSEEK_MODEL", "deepseek-v4-flash");
    const valid = {
      slotAnalysis: {
        requiredFunctions: [],
        preferredFunctions: [],
        dependencies: [],
        replacementRisks: [],
      },
      candidates: [evaluation("10000031", 80)],
    };
    const responses = [
      envelope(""),
      envelope(JSON.stringify(valid)),
    ];
    const fetchImpl = vi.fn(
      async (
        input: RequestInfo | URL,
        init?: RequestInit,
      ): Promise<Response> => {
        void input;
        void init;
        return responses.shift()!;
      },
    );
    const client = new DeepSeekReplacementClient({
      fetchImpl: fetchImpl as unknown as typeof fetch,
      sleep: async () => undefined,
      random: () => 0,
    });
    const input = buildEvaluationInput({
      gameDataVersion: "game-v1",
      team,
      replacingCharacterId: "10000052",
      teamArchetype: "reaction",
      profiles,
    });
    const result = await client.evaluate(input);
    expect(result.attempts).toBe(2);
    expect(result.result.candidates[0]?.characterId).toBe("10000031");
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    const request = fetchImpl.mock.calls[0]?.[1];
    if (!request) throw new Error("missing request");
    const requestBody = JSON.parse(String(request.body)) as {
      messages: Array<{ content: string }>;
    };
    expect(requestBody.messages[1]?.content).toContain('"allowedCandidateIds"');
    expect(request.body).not.toContain("test-only-secret");
  });
});

function profile(
  characterId: string,
  roles: string[],
  tags: string[],
  fieldTime: CharacterTeamProfile["fieldTime"],
  damagePosition: CharacterTeamProfile["damagePosition"],
  element: string,
  healing = false,
): CharacterTeamProfile {
  return {
    characterId,
    element,
    roles,
    tags,
    fieldTime,
    damagePosition,
    application: { elements: [element], offField: damagePosition !== "on_field" },
    utility: healing ? { healing: "team" } : undefined,
    dataVersion: "profiles-v1",
  };
}

function evaluation(characterId: string, score: number) {
  return {
    characterId,
    compatibilityScore: score,
    category: "optimal" as const,
    confidence: 0.9,
    reasons: ["structured match"],
    tradeoffs: [],
    requiredChanges: [],
    teamEvaluation: {
      reactionViability: score,
      damageBalance: score,
      sustain: score,
      energy: score,
      fieldTimeBalance: score,
    },
  };
}

function envelope(content: string): Response {
  return new Response(
    JSON.stringify({
      choices: [{ message: { content }, finish_reason: "stop" }],
      usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 },
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
}
