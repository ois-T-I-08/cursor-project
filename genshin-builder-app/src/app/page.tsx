import Link from "next/link";
import { getRecentProgress } from "@/lib/repository/progress";
import { getUserId } from "@/lib/user";
import ProgressCard from "@/components/character/ProgressCard";

/**
 * ホーム画面（Server Component）
 * - 最近編集したキャラクター（DBの育成状況から取得）
 * - お知らせ用エリア（将来用）
 */
export default async function HomePage() {
  const userId = await getUserId();
  const recentItems = userId ? await getRecentProgress(userId, 4) : [];

  return (
    <div className="space-y-8">
      {/* ヒーローエリア */}
      <section className="rounded-2xl border border-white/10 bg-gradient-to-br from-[#1e2a3a] to-[#151d2a] p-6 sm:p-8">
        <h1 className="text-2xl font-bold sm:text-3xl">
          <span className="bg-gradient-to-r from-[#f0c674] to-[#d4a853] bg-clip-text text-transparent">
            Genshin Builder
          </span>
        </h1>
        <p className="mt-2 text-sm text-gray-400 sm:text-base">
          原神のキャラクター育成状況をまとめて管理。レベル・天賦・武器の進捗をひと目で確認できます。
        </p>
        <Link
          href="/characters"
          className="mt-4 inline-block rounded-lg bg-gradient-to-r from-[#d4a853] to-[#b8923f] px-5 py-2 text-sm font-medium text-gray-900 transition-transform hover:-translate-y-0.5"
        >
          キャラクター一覧を見る
        </Link>
      </section>

      {/* 最近編集したキャラクター */}
      <section>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-lg font-bold">最近編集したキャラクター</h2>
          <Link
            href="/characters"
            className="text-sm text-accent hover:underline"
          >
            すべて見る →
          </Link>
        </div>

        {recentItems.length > 0 ? (
          <div className="grid gap-3 sm:grid-cols-2">
            {recentItems.map((item) => (
              <ProgressCard key={item.character.id} item={item} />
            ))}
          </div>
        ) : (
          <p className="rounded-xl border border-white/10 bg-[#1e2a3a] p-8 text-center text-sm text-gray-500">
            まだ育成データがありません。キャラクター一覧から選んで育成状況を登録しましょう。
          </p>
        )}
      </section>

      {/* お知らせエリア（将来用） */}
      <section>
        <h2 className="mb-3 text-lg font-bold">お知らせ</h2>
        <div className="rounded-xl border border-white/10 bg-[#1e2a3a] p-4">
          <p className="text-sm text-gray-400">
            現在お知らせはありません。今後のアップデート情報をここに掲載予定です。
          </p>
        </div>
      </section>
    </div>
  );
}
