import { describe, expect, it } from "vitest";
import {
  isCharacterBuildGuideTitle,
  resolvePrimaryCharacterFromTitle,
} from "@/lib/build-guides/character-match-logic";

const hints = [
  { id: "10000041", name: "モナ" },
  { id: "10000133", name: "サンドローネ" },
  { id: "10000087", name: "ヌヴィレット" },
  { id: "10000125", name: "コロンビーナ" },
];

describe("resolvePrimaryCharacterFromTitle", () => {
  it("prefers 「quoted」 name over other mentions", () => {
    expect(
      resolvePrimaryCharacterFromTitle(
        "【原神】氷元素版ヌヴィレット！？「サンドローネ」を引く人向けガイド",
        hints,
      ),
    ).toBe("10000133");
  });

  it("falls back to longest name match", () => {
    expect(
      resolvePrimaryCharacterFromTitle(
        "【原神】コロンビーナ最新解説！おすすめ武器・聖遺物",
        hints,
      ),
    ).toBe("10000125");
  });
});

describe("isCharacterBuildGuideTitle", () => {
  it("accepts build guides and rejects gacha-only titles", () => {
    expect(
      isCharacterBuildGuideTitle(
        "【原神】「モナ」最新解説！おすすめ武器・聖遺物・目標ステータス",
      ),
    ).toBe(true);
    expect(
      isCharacterBuildGuideTitle(
        "【原神】LunaⅧガチャ優先度を徹底解説！",
      ),
    ).toBe(false);
  });
});
