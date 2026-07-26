import { describe, expect, it } from "vitest";

import {
  buildCharacterIdMapFromAmberData,
  CharacterIdMapGenerateError,
  CHARACTER_ID_MAP_MAX_DROP_RATIO,
  CHARACTER_ID_MAP_MIN_COUNT,
  diffCharacterIdMaps,
  parseCharacterIdMapSource,
  renderCharacterIdMapSource,
} from "@/lib/yshelper/character-id-map-generate";

const MIN = 3;

function amberPayload(
  entries: Array<{ id: string; name: string }>,
): Record<string, unknown> {
  const items: Record<string, unknown> = {};
  for (const entry of entries) {
    items[entry.id] = {
      id: entry.id,
      name: entry.name,
      ignored: { nested: true },
    };
  }
  return {
    response: 200,
    unused: "ok",
    data: {
      props: { ignored: true },
      types: { ignored: true },
      items,
    },
  };
}

function padWithAmber(
  extras: Array<{ id: string; name: string }> = [],
): Record<string, unknown> {
  return amberPayload([
    { id: "10000021", name: "Amber" },
    { id: "10000014", name: "Barbara" },
    { id: "10000016", name: "Diluc" },
    ...extras,
  ]);
}

function expectCode(fn: () => unknown, code: string): void {
  try {
    fn();
    expect.fail(`expected ${code}`);
  } catch (error) {
    expect(error).toBeInstanceOf(CharacterIdMapGenerateError);
    expect(error).toMatchObject({ code });
  }
}

describe("buildCharacterIdMapFromAmberData", () => {
  it("builds a sorted map with Ambor alias and ignores unknown fields", () => {
    const { map, count } = buildCharacterIdMapFromAmberData(
      padWithAmber([{ id: "10000032", name: "Bennett" }]),
      null,
      { minCount: MIN },
    );
    expect(count).toBe(5);
    expect(Object.keys(map)).toEqual([
      "amber",
      "ambor",
      "barbara",
      "bennett",
      "diluc",
    ]);
    expect(map.ambor).toBe(map.amber);
    expect(map.amber).toBe("10000021");
  });

  it("renders a stable source for the same input", () => {
    const { map } = buildCharacterIdMapFromAmberData(padWithAmber(), null, {
      minCount: MIN,
    });
    const first = renderCharacterIdMapSource(map);
    const second = renderCharacterIdMapSource(
      buildCharacterIdMapFromAmberData(padWithAmber(), null, {
        minCount: MIN,
      }).map,
    );
    expect(first).toBe(second);
    expect(parseCharacterIdMapSource(first)).toEqual(map);
  });

  it("excludes Traveler by id and name", () => {
    const { map } = buildCharacterIdMapFromAmberData(
      amberPayload([
        { id: "10000021", name: "Amber" },
        { id: "10000005", name: "Traveler" },
        { id: "10000007", name: "Aether" },
        { id: "10000014", name: "Barbara" },
        { id: "10000016", name: "Diluc" },
      ]),
      null,
      { minCount: MIN },
    );
    expect(map.traveler).toBeUndefined();
    expect(map.aether).toBeUndefined();
    expect(Object.keys(map)).toContain("ambor");
  });

  it("rejects duplicate names with different ids", () => {
    expectCode(
      () =>
        buildCharacterIdMapFromAmberData(
          amberPayload([
            { id: "10000021", name: "Amber" },
            { id: "10000014", name: "Barbara" },
            { id: "10000016", name: "Barbara" },
          ]),
          null,
          { minCount: MIN },
        ),
      "duplicate_character_name",
    );
  });

  it("rejects duplicate ids with different names", () => {
    expectCode(
      () =>
        buildCharacterIdMapFromAmberData(
          {
            data: {
              items: {
                "10000021": { id: "10000021", name: "Amber" },
                "10000021b": { id: "10000021", name: "Other" },
                "10000014": { id: "10000014", name: "Barbara" },
              },
            },
          },
          null,
          { minCount: MIN },
        ),
      "duplicate_character_id",
    );
  });

  it("rejects payloads whose items have no numeric character ids", () => {
    expectCode(
      () =>
        buildCharacterIdMapFromAmberData(
          amberPayload([
            { id: "not-a-number", name: "Amber" },
            { id: "also-bad", name: "Barbara" },
          ]),
          null,
          { minCount: MIN },
        ),
      "invalid_character_id",
    );
  });

  it("rejects mismatched key and id fields", () => {
    expectCode(
      () =>
        buildCharacterIdMapFromAmberData(
          {
            data: {
              items: {
                "10000021": { id: "10000099", name: "Amber" },
                "10000014": { id: "10000014", name: "Barbara" },
                "10000016": { id: "10000016", name: "Diluc" },
              },
            },
          },
          null,
          { minCount: MIN },
        ),
      "character_id_mismatch",
    );
  });

  it("rejects empty character names", () => {
    expectCode(
      () =>
        buildCharacterIdMapFromAmberData(
          amberPayload([
            { id: "10000021", name: "   " },
            { id: "10000014", name: "Barbara" },
          ]),
          null,
          { minCount: MIN },
        ),
      "empty_character_name",
    );
  });

  it("fails when Amber is missing", () => {
    expectCode(
      () =>
        buildCharacterIdMapFromAmberData(
          amberPayload([
            { id: "10000014", name: "Barbara" },
            { id: "10000016", name: "Diluc" },
            { id: "10000032", name: "Bennett" },
          ]),
          null,
          { minCount: MIN },
        ),
      "amber_missing",
    );
  });

  it("rejects maps below the absolute minimum count", () => {
    expect(CHARACTER_ID_MAP_MIN_COUNT).toBeGreaterThanOrEqual(80);
    expectCode(
      () => buildCharacterIdMapFromAmberData(padWithAmber(), null),
      "map_too_small",
    );
  });

  it("rejects an abnormal count drop versus the previous map", () => {
    expect(CHARACTER_ID_MAP_MAX_DROP_RATIO).toBe(0.8);
    const previous = Object.fromEntries(
      Array.from({ length: 20 }, (_, index) => [
        `char${index}`,
        String(10000000 + index),
      ]),
    );
    previous.amber = "10000021";
    expectCode(
      () =>
        buildCharacterIdMapFromAmberData(padWithAmber(), previous, {
          minCount: MIN,
          maxDropRatio: CHARACTER_ID_MAP_MAX_DROP_RATIO,
        }),
      "map_count_drop",
    );
  });

  it("rejects a missing data field", () => {
    expectCode(
      () =>
        buildCharacterIdMapFromAmberData({ response: 200 }, null, {
          minCount: MIN,
        }),
      "missing_amber_data",
    );
  });

  it("rejects a missing items map", () => {
    expectCode(
      () =>
        buildCharacterIdMapFromAmberData(
          { response: 200, data: { props: {}, types: {} } },
          null,
          { minCount: MIN },
        ),
      "missing_amber_items",
    );
  });

  it("diffCharacterIdMaps reports added removed and changed keys", () => {
    expect(
      diffCharacterIdMaps(
        { amber: "10000021", barbara: "10000014" },
        { amber: "10000021", diluc: "10000016", barbara: "99999999" },
      ),
    ).toEqual({
      added: ["diluc"],
      removed: [],
      changed: ["barbara"],
    });
  });

  it("check equality is based on rendered source bytes", () => {
    const { map } = buildCharacterIdMapFromAmberData(padWithAmber(), null, {
      minCount: MIN,
    });
    const source = renderCharacterIdMapSource(map);
    expect(source.replace(/\r\n/g, "\n")).toBe(
      renderCharacterIdMapSource(map).replace(/\r\n/g, "\n"),
    );
    expect(source).not.toContain("not-a-number");
  });
});
