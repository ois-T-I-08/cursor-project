"use client";

/**
 * ルートエラー表示（Client Component）。
 *
 * Next.js App Router の規約により、このコンポーネントは
 * ルートレイアウト配下のエラーを捕捉し、フォールバック UI を表示する。
 *
 * ユーザーに内部エラーの詳細を表示せず、再試行ボタンを提供する。
 * digest はエラー識別用のハッシュで、安全に表示可能。
 */
import { useEffect } from "react";

interface RootErrorProps {
  error: Error & { digest?: string };
  reset: () => void;
}

export default function RootError({ error, reset }: RootErrorProps) {
  // 本番環境ではエラーログへ記録（実際のログ基盤と連携可能）
  useEffect(() => {
    console.error("Unhandled page error:", error);
  }, [error]);

  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <div className="text-center" role="alert">
        <p className="text-lg font-medium text-white/80">
          エラーが発生しました
        </p>
        <p className="mt-1 text-sm text-white/40">
          時間をおいて再度お試しください。
        </p>
        {error.digest && (
          <p className="mt-2 text-xs text-white/20 font-mono">
            ID: {error.digest}
          </p>
        )}
        <button
          onClick={reset}
          className="mt-6 rounded-lg bg-accent px-5 py-2 text-sm font-medium text-[#0f1419] transition hover:brightness-110 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >
          再試行
        </button>
      </div>
    </div>
  );
}
