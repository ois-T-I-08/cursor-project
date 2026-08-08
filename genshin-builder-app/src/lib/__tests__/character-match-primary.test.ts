import { describe, expect, it } from "vitest";
import {
  CHARACTER_TITLE_ALIASES,
  isAmbiguousMultiCharacterTitle,
  isCharacterBuildGuideTitle,
  resolvePrimaryCharacterFromTitle,
} from "@/lib/build-guides/character-match-logic";

const hints = [
  { id: "10000041", name: "モナ" },
  { id: "10000133", name: "サンドローネ" },
  { id: "10000087", name: "ヌヴィレット" },
  { id: "10000125", name: "コロンビーナ" },
  { id: "10000091", name: "アルレッキーノ" },
  { id: "10000054", name: "珊瑚宮心海" },
  { id: "10000047", name: "楓原万葉" },
  { id: "10000046", name: "胡桃" },
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

  it("F: 「召使」 → アルレッキーノ", () => {
    expect(CHARACTER_TITLE_ALIASES["召使"]).toBe("アルレッキーノ");
    expect(
      resolvePrimaryCharacterFromTitle(
        "【原神】「召使」最新解説！おすすめ武器・聖遺物・目標ステータス",
        hints,
      ),
    ).toBe("10000091");
  });

  it("G: 「心海」 → 珊瑚宮心海", () => {
    expect(
      resolvePrimaryCharacterFromTitle(
        "【原神】「心海」育成ガイド！おすすめ武器・聖遺物",
        hints,
      ),
    ).toBe("10000054");
  });

  it("H: 「万葉」 → 楓原万葉", () => {
    expect(
      resolvePrimaryCharacterFromTitle(
        "【原神】「万葉」おすすめ武器・聖遺物ガイド",
        hints,
      ),
    ).toBe("10000047");
  });

  it("I: 「アリョーシャ」 → unresolved when not in master", () => {
    expect(
      resolvePrimaryCharacterFromTitle(
        "【原神】回復持ち星反応バッファー！？「アリョーシャ」を引く人向けオススメ武器・聖遺物ガイド【げんしん】",
        hints,
      ),
    ).toBeNull();
  });

  it("J: multi-character artifact titles do not force a single primary", () => {
    const titles = [
      "【原神】星反応が超絶強化！Ver7.0新聖遺物の強すぎる性能とおすすめキャラ【げんしん】",
      "【原神】◯◯は乗り換え必須！新聖遺物で評価が変わるキャラと残すべき聖遺物【げんしん】",
      "【原神】まさかの隠し仕様が発覚！新聖遺物を装備すべきキャラと避けるべきキャラ【げんしん】",
      "【原神】ダメージ◯◯倍！？新聖遺物に乗り換え必須キャラを解説！【げんしん】",
    ];
    for (const title of titles) {
      expect(isAmbiguousMultiCharacterTitle(title)).toBe(true);
      expect(resolvePrimaryCharacterFromTitle(title, hints)).toBeNull();
    }
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
