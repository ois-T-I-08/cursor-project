"use client";

/**
 * グローバルエラー表示（Client Component）。
 *
 * ルートレイアウト自体がクラッシュした場合に表示される
 * 最終フォールバック。html/body タグを含む完全な HTML を
 * 自力でレンダリングする必要がある。
 */
interface GlobalErrorProps {
  error: Error & { digest?: string };
  unstable_retry: () => void;
}

export default function GlobalError({ unstable_retry }: GlobalErrorProps) {
  return (
    <html lang="ja">
      <body className="m-0 bg-[#0f1419] p-0 text-[#e8e6e3] antialiased">
        <div className="flex min-h-screen items-center justify-center">
          <div className="text-center" role="alert">
            <p className="text-xl font-medium">Genshin Builder</p>
            <p className="mt-4 text-lg text-white/80">
              エラーが発生しました
            </p>
            <p className="mt-1 text-sm text-white/40">
              時間をおいて再度お試しください。
            </p>
            <button
              onClick={unstable_retry}
              className="mt-6 rounded-lg bg-[#d4a853] px-5 py-2 text-sm font-medium text-[#0f1419] transition hover:brightness-110 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#d4a853]"
            >
              再試行
            </button>
          </div>
        </div>
      </body>
    </html>
  );
}
