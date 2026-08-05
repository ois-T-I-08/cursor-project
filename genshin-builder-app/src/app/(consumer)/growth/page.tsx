import type { Metadata } from "next";
import ConsumerPage from "@/components/consumer/ConsumerPage";
import ConsumerStatePanel from "@/components/consumer/ConsumerStatePanel";

export const metadata: Metadata = { title: "育成" };

export default function GrowthPage() {
  return (
    <ConsumerPage
      title="育成"
      description="キャラクターや武器の育成目標と、必要な素材をまとめて確認するための画面です。"
    >
      <ConsumerStatePanel
        state="unavailable"
        title="育成計画の一覧は準備中です"
        description="現在の育成状況はキャラクター画面で確認できます。ここでは架空の進捗や計算結果を表示せず、実データを安全に読み取れる段階から提供します。"
        action={{ href: "/characters", label: "現在の育成状況を見る" }}
      />
    </ConsumerPage>
  );
}
