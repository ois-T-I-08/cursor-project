import type { Metadata } from "next";
import ConsumerPage from "@/components/consumer/ConsumerPage";
import ConsumerStatePanel from "@/components/consumer/ConsumerStatePanel";

export const metadata: Metadata = { title: "編成" };

export default function TeamsPage() {
  return (
    <ConsumerPage
      title="編成"
      description="所持キャラクターをもとに編成候補を確認し、比較するための画面です。"
    >
      <ConsumerStatePanel
        state="unavailable"
        title="Web版の編成表示は準備中です"
        description="検証済みの編成データを安全に読み取る経路が整うまで、架空の編成やAI提案は表示しません。編成の編集や保存もこの画面では行いません。"
      />
    </ConsumerPage>
  );
}
