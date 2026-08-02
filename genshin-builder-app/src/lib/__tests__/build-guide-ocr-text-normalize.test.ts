import { describe, expect, it } from "vitest";
import {
  normalizeOcrVisibleText,
  numberInNormalizedVisibleText,
} from "../build-guides/ocr-text-normalize";

describe("ocr-text-normalize", () => {
  it("normalizes fullwidth digits and OCR O/l confusions", () => {
    expect(normalizeOcrVisibleText("ＥＲ　１５Ｏ％")).toContain("150");
    expect(normalizeOcrVisibleText("会心 6l%")).toContain("61");
  });

  it("grounds numbers after normalization", () => {
    expect(
      numberInNormalizedVisibleText("ER 15O%", [null, 150, null]),
    ).toBe(true);
    expect(
      numberInNormalizedVisibleText("攻撃力 ２，０５０", [2050, null, null]),
    ).toBe(true);
  });
});
