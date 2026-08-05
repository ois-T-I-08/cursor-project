import Link from "next/link";

/**
 * カスタム404ページ。
 *
 * `notFound()` が呼ばれた場合や、存在しないパスに
 * アクセスした場合に表示される。
 */
export default function NotFound() {
  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <div className="text-center" role="alert">
        <p className="text-lg font-medium">
          ページが見つかりません
        </p>
        <p className="consumer-muted mt-1 text-sm">
          指定されたページは存在しないか、削除された可能性があります。
        </p>
        <Link
          href="/today"
          className="consumer-button mt-6 inline-flex"
        >
          今日の画面へ戻る
        </Link>
      </div>
    </div>
  );
}
