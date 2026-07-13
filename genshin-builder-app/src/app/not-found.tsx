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
        <p className="text-lg font-medium text-white/80">
          ページが見つかりません
        </p>
        <p className="mt-1 text-sm text-white/40">
          指定されたページは存在しないか、削除された可能性があります。
        </p>
        <Link
          href="/"
          className="mt-6 inline-block rounded-lg bg-accent px-5 py-2 text-sm font-medium text-[#0f1419] transition hover:brightness-110 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >
          ホームに戻る
        </Link>
      </div>
    </div>
  );
}
