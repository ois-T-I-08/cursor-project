/**
 * 同期時の API 呼び出しを抑えるヘルパー
 */

/** 1 トランザクションあたりの upsert 件数（ロック時間を抑える） */
export const UPSERT_BATCH_SIZE = 50;

/** Prisma の notIn に空配列を渡すと例外になるためガードする */
export function idsForNotIn(ids: string[]): string[] | undefined {
  return ids.length > 0 ? ids : undefined;
}

/** 配列を指定サイズのバッチに分割して逐次処理する */
export async function forEachBatch<T>(
  items: T[],
  batchSize: number,
  processBatch: (batch: T[]) => Promise<void>,
): Promise<void> {
  for (let i = 0; i < items.length; i += batchSize) {
    await processBatch(items.slice(i, i + batchSize));
  }
}
