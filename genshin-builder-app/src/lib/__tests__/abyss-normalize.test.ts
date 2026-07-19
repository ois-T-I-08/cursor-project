import { describe, expect, it } from "vitest";

import { AbyssStatisticsError } from "@/lib/api/abyss/errors";
import { normalizeAzaAbyssStatistics } from "@/lib/api/abyss/normalize-aza";
import { validAzaPayload } from "./fixtures/aza-abyss";

describe("normalizeAzaAbyssStatistics", () => {
  it("normalizes rates, halves, teams, weapons, artifacts, and metadata", () => {
    const result = normalizeAzaAbyssStatistics(validAzaPayload());

    expect(result.version).toEqual({
      scheduleId: 121,
      periodStart: "2026-07-15T20:00:00.000Z",
      periodEnd: "2026-08-15T19:59:59.000Z",
      sourceApiVersion: "5.6",
    });
    expect(result.metadata).toMatchObject({
      source: "AZA.GG",
      sampleSize: 1_111,
      referenceSampleSize: 2_000,
      collectionProgress: 0.668,
    });
    expect(result.characters[0]).toMatchObject({
      characterId: "10000125",
      usageRate: 0.871,
      ownershipRate: 0.967,
      usageAmongOwnersRate: 0.901,
      upperHalfRate: 0.031,
      lowerHalfRate: 0.969,
      constellationRates: [
        { constellation: 0, rate: 0.658 },
        { constellation: 2, rate: 0.187 },
      ],
      weapons: [{ id: "14522", usageRate: 0.476 }],
      artifacts: [
        {
          setPieces: [{ artifactSetId: "15042", pieces: 4 }],
          usageRate: 0.496,
        },
      ],
    });
    expect(result.teams).toEqual([
      {
        half: "upper",
        members: ["10000133", "10000112", "10000058", "10000035"],
        usageRate: 0.207,
        ownershipRate: 0.548,
        usageAmongOwnersRate: 0.377,
      },
      {
        half: "lower",
        members: ["10000125", "10000116", "10000103", "10000043"],
        usageRate: 0.101,
        ownershipRate: 0.62,
        usageAmongOwnersRate: 0.163,
      },
    ]);
  });

  it("accepts the observed single-object artifact shape", () => {
    const payload = validAzaPayload();
    const data = payload.data as Record<string, unknown>;
    const characters = data.character as Record<string, Record<string, unknown>>;
    characters["10000125"].artifacts = {
      set: { "15046": 4 },
      value: 1,
    };

    expect(
      normalizeAzaAbyssStatistics(payload).characters[0].artifacts,
    ).toEqual([
      {
        setPieces: [{ artifactSetId: "15046", pieces: 4 }],
        usageRate: 1,
      },
    ]);
  });

  it("drops incomplete parties instead of presenting them as four-person teams", () => {
    const payload = validAzaPayload();
    const data = payload.data as Record<string, unknown>;
    const party = data.party as Record<string, unknown[]>;
    party["1"].unshift({
      id: "10000133,10000058",
      use_rate: 0.5,
      own_rate: 0.5,
      use_by_own_rate: 1,
    });

    const result = normalizeAzaAbyssStatistics(payload);
    expect(result.teams).toHaveLength(2);
    expect(result.teams.every((team) => team.members.length === 4)).toBe(true);
  });

  describe("character phase rates", () => {
    it("uses the complement when only phase 1 exists", () => {
      const result = normalizeAzaAbyssStatistics(withPhase({ "1": 0.25 }));

      expect(result.characters[0]).toMatchObject({
        upperHalfRate: 0.25,
        lowerHalfRate: 0.75,
      });
    });

    it("prefers an explicit valid phase 2 over the phase 1 complement", () => {
      const result = normalizeAzaAbyssStatistics(
        withPhase({ "1": 0.25, "2": 0.6 }),
      );

      expect(result.characters[0]).toMatchObject({
        upperHalfRate: 0.25,
        lowerHalfRate: 0.6,
      });
    });

    it("keeps an explicit null phase 2 unavailable instead of inferring it", () => {
      const result = normalizeAzaAbyssStatistics(
        withPhase({ "1": 0.25, "2": null }),
      );

      expect(result.characters[0]).toMatchObject({
        upperHalfRate: 0.25,
        lowerHalfRate: null,
      });
    });

    it("accepts an explicit phase 2 when phase 1 is unavailable", () => {
      const result = normalizeAzaAbyssStatistics(withPhase({ "2": 0.6 }));

      expect(result.characters[0]).toMatchObject({
        upperHalfRate: null,
        lowerHalfRate: 0.6,
      });
    });

    it.each([
      [0, 1],
      [1, 0],
      [0.30000000000000004, 0.7],
    ])("clamps the phase 1 complement for %s", (upper, lower) => {
      const result = normalizeAzaAbyssStatistics(withPhase({ "1": upper }));

      expect(result.characters[0]).toMatchObject({
        upperHalfRate: upper,
        lowerHalfRate: lower,
      });
    });

    it.each([undefined, null])(
      "treats a %s phase object as unavailable",
      (phase) => {
        const result = normalizeAzaAbyssStatistics(withPhase(phase));

        expect(result.characters[0]).toMatchObject({
          upperHalfRate: null,
          lowerHalfRate: null,
        });
      },
    );

    it("treats missing and null phase entries as unavailable", () => {
      for (const phase of [{}, { "1": null, "2": null }]) {
        const result = normalizeAzaAbyssStatistics(withPhase(phase));
        expect(result.characters[0]).toMatchObject({
          upperHalfRate: null,
          lowerHalfRate: null,
        });
      }
    });

    it.each([
      ["phase 1 below zero", { "1": -0.01 }],
      ["phase 1 above one", { "1": 1.01 }],
      ["phase 2 below zero", { "1": 0.5, "2": -0.01 }],
      ["phase 2 above one", { "1": 0.5, "2": 1.01 }],
      ["phase 1 non-number", { "1": "0.5" }],
      ["phase 2 non-number", { "1": 0.5, "2": "0.5" }],
    ])("rejects %s", (_, phase) => {
      expect(() => normalizeAzaAbyssStatistics(withPhase(phase))).toThrow(
        AbyssStatisticsError,
      );
    });
  });

  it.each([
    ["missing required field", (payload: Record<string, unknown>) => {
      const data = payload.data as Record<string, unknown>;
      delete data.schedule;
    }],
    ["out-of-range rate", (payload: Record<string, unknown>) => {
      const data = payload.data as Record<string, unknown>;
      const characters = data.character as Record<string, Record<string, unknown>>;
      characters["10000125"].use_rate = 87.1;
    }],
    ["invalid response code", (payload: Record<string, unknown>) => {
      payload.retcode = -1;
    }],
  ])("rejects %s", (_, mutate) => {
    const payload = validAzaPayload();
    mutate(payload);
    expect(() => normalizeAzaAbyssStatistics(payload)).toThrow(
      AbyssStatisticsError,
    );
  });
});

function withPhase(phase: unknown): Record<string, unknown> {
  const payload = validAzaPayload();
  const data = payload.data as Record<string, unknown>;
  const characters = data.character as Record<string, Record<string, unknown>>;
  if (phase === undefined) {
    delete characters["10000125"].phase;
  } else {
    characters["10000125"].phase = phase;
  }
  return payload;
}
