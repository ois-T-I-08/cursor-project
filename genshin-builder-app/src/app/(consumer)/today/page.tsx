import type { Metadata } from "next";
import ConsumerPage from "@/components/consumer/ConsumerPage";
import ConsumerStatePanel from "@/components/consumer/ConsumerStatePanel";
import TodayPlan from "@/components/consumer/TodayPlan";
import ProgressCard from "@/components/character/ProgressCard";
import { getRecentProgress } from "@/lib/repository/progress";
import { getUserId } from "@/lib/user";

export const metadata: Metadata = { title: "今日" };
export const dynamic = "force-dynamic";

export default async function TodayPage() {
  const userId = await getUserId();
  const recentItems = userId ? await getRecentProgress(userId, 4) : [];

  return (
    <ConsumerPage
      title="今日"
      description="今日取り組む育成を、優先度の高い順に確認する画面です。Web版では安全な読み取り基盤から段階的に提供します。"
    >
      <TodayPlan proposal={null} />

      <section className="space-y-3" aria-labelledby="recent-progress-heading">
        <h2 id="recent-progress-heading" className="text-lg font-bold">
          最近更新した育成状況
        </h2>
        {recentItems.length > 0 ? (
          <div className="legacy-dark-surface grid gap-3 rounded-2xl bg-[#0f1419] p-3 sm:grid-cols-2">
            {recentItems.map((item) => (
              <ProgressCard key={item.character.id} item={item} />
            ))}
          </div>
        ) : (
          <ConsumerStatePanel
            state="empty"
            title="育成状況はまだ登録されていません"
            description="キャラクター画面で育成状況を登録すると、最近更新した内容をここで確認できます。"
            action={{ href: "/characters", label: "キャラクターを見る" }}
          />
        )}
      </section>
    </ConsumerPage>
  );
}
