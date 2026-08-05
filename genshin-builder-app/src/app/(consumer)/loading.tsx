import ConsumerStatePanel from "@/components/consumer/ConsumerStatePanel";

export default function ConsumerLoading() {
  return (
    <ConsumerStatePanel
      state="loading"
      title="画面を準備しています"
      description="最新の情報を確認しています。しばらくお待ちください。"
    />
  );
}
