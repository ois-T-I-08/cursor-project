/**
 * ルートローディング表示。
 * サーバーサイドのデータ取得中に表示されるスケルトン。
 * 過剰なアニメーションを避け、既存レイアウト（Header + main + Footer）と
 * 調和する簡潔な表示にする。
 */
export default function RootLoading() {
  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <div className="text-center" role="status" aria-label="読み込み中">
        <div
          className="mx-auto mb-3 h-8 w-8 animate-spin rounded-full border-2 border-app-border border-t-accent"
          aria-hidden="true"
        />
        <p className="consumer-muted text-sm">読み込み中...</p>
      </div>
    </div>
  );
}
