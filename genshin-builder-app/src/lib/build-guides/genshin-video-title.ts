/** 管理画面・同期で原神ガイド動画とみなすタイトルマーカー */
export const GENSIN_VIDEO_TITLE_MARKER = "【原神】";

export function isGenshinTitledVideo(title: string): boolean {
  return title.includes(GENSIN_VIDEO_TITLE_MARKER);
}
