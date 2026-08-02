import { describe, expect, it } from "vitest";
import {
  GENSIN_VIDEO_TITLE_MARKER,
  isGenshinTitledVideo,
} from "@/lib/build-guides/genshin-video-title";

describe("isGenshinTitledVideo", () => {
  it("accepts titles containing 【原神】", () => {
    expect(isGenshinTitledVideo("【原神】ナヴィア育成ガイド")).toBe(true);
    expect(isGenshinTitledVideo(`前置き ${GENSIN_VIDEO_TITLE_MARKER} 後半`)).toBe(
      true,
    );
  });

  it("rejects titles without the marker", () => {
    expect(isGenshinTitledVideo("原神 攻略")).toBe(false);
    expect(isGenshinTitledVideo("【崩壊スターレイル】解説")).toBe(false);
    expect(isGenshinTitledVideo("")).toBe(false);
  });
});
