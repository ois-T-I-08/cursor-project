"use client";

/**
 * ルートエラー表示（Client Component）。
 *
 * Next.js App Router の規約により、このコンポーネントは
 * ルートレイアウト配下のエラーを捕捉し、フォールバック UI を表示する。
 *
 * ユーザーに内部エラーの詳細を表示せず、再試行ボタンを提供する。
 */
interface RootErrorProps {
  error: Error & { digest?: string };
  unstable_retry: () => void;
}

export default function RootError({ unstable_retry }: RootErrorProps) {
  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <div className="text-center" role="alert">
        <p className="text-lg font-medium">
          エラーが発生しました
        </p>
        <p className="consumer-muted mt-1 text-sm">
          時間をおいて再度お試しください。
        </p>
        <button
          onClick={unstable_retry}
          className="consumer-button mt-6"
        >
          再試行
        </button>
      </div>
    </div>
  );
}
