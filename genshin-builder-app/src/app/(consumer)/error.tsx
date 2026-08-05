"use client";

import ConsumerStatePanel from "@/components/consumer/ConsumerStatePanel";

export default function ConsumerError({
  unstable_retry,
}: {
  error: Error & { digest?: string };
  unstable_retry: () => void;
}) {
  return (
    <div className="space-y-4">
      <ConsumerStatePanel
        state="error"
        title="画面を読み込めませんでした"
        description="通信状況を確認して、もう一度お試しください。入力や保存済みデータがこの操作で変更されることはありません。"
      />
      <button type="button" onClick={unstable_retry} className="consumer-button">
        もう一度試す
      </button>
    </div>
  );
}
