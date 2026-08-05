import type { Metadata } from "next";
import { getSyncStatus } from "@/lib/repository/characters";
import { getUserId } from "@/lib/user";
import SyncSection from "@/components/settings/SyncSection";
import ConsumerPage from "@/components/consumer/ConsumerPage";

export const metadata: Metadata = {
  title: "設定",
};

// 同期直後に最新の件数を表示するため毎回レンダリングする
export const dynamic = "force-dynamic";

/** 日時を「2026/7/7 23:50」形式にする */
function formatDateTime(date: Date): string {
  return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()} ${date.getHours()}:${String(date.getMinutes()).padStart(2, "0")}`;
}

/**
 * 設定画面
 * マスターデータの同期・データ管理を行う。
 */
export default async function SettingsPage() {
  const [syncStatus, userId] = await Promise.all([
    getSyncStatus(),
    getUserId(),
  ]);
  const counts = syncStatus;

  return (
    <ConsumerPage
      title="設定"
      description="ゲームデータの同期状況と、このブラウザで利用している匿名データの状態を確認します。"
    >
      <div className="legacy-dark-surface space-y-4 rounded-2xl bg-[#0f1419] p-3 text-[#e8e6e3] sm:p-5">

      <section className="rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
        <h2 className="font-bold">ゲームデータ同期</h2>
        <p className="mt-1 text-sm text-gray-400">
          キャラクター・武器・素材・突破データを外部API（Project Amber）から取得してデータベースへ保存します。
          ゲーム更新後は「ゲームデータを同期」を実行してください。
        </p>

        <dl className="mt-3 grid grid-cols-2 gap-2 text-sm sm:grid-cols-3 lg:grid-cols-4">
          <div className="rounded-lg bg-[#151d2a] p-3">
            <dt className="text-xs text-gray-500">キャラクター</dt>
            <dd className="mt-0.5 font-bold text-accent">{counts.characters} 件</dd>
          </div>
          <div className="rounded-lg bg-[#151d2a] p-3">
            <dt className="text-xs text-gray-500">武器</dt>
            <dd className="mt-0.5 font-bold text-accent">{counts.weapons} 件</dd>
          </div>
          <div className="rounded-lg bg-[#151d2a] p-3">
            <dt className="text-xs text-gray-500">素材</dt>
            <dd className="mt-0.5 font-bold text-accent">{counts.materials} 件</dd>
          </div>
          <div className="rounded-lg bg-[#151d2a] p-3">
            <dt className="text-xs text-gray-500">突破データ</dt>
            <dd className="mt-0.5 text-xs font-bold text-accent">
              キャラ {counts.characterUpgrades} / 武器 {counts.weaponUpgrades}
            </dd>
          </div>
          <div className="rounded-lg bg-[#151d2a] p-3">
            <dt className="text-xs text-gray-500">EXP表</dt>
            <dd className="mt-0.5 font-bold text-accent">
              {counts.levelExpSegments} 件
            </dd>
          </div>
          <div className="rounded-lg bg-[#151d2a] p-3">
            <dt className="text-xs text-gray-500">最終同期</dt>
            <dd className="mt-0.5 text-xs font-bold text-gray-300">
              {counts.lastSyncedAt ? formatDateTime(counts.lastSyncedAt) : "未同期"}
            </dd>
          </div>
        </dl>

        <div className="mt-4">
          <SyncSection status={syncStatus} />
        </div>
      </section>

      <section className="rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
        <h2 className="font-bold">データ管理</h2>
        <p className="mt-1 text-sm text-gray-400">
          育成データのエクスポート／インポート機能を今後追加予定です。
        </p>
      </section>

      <section className="rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
        <h2 className="font-bold">アカウント</h2>
        <p className="mt-1 text-sm text-gray-400">
          現在はブラウザごとの匿名IDでデータを管理します。将来的にGoogleログインなどを追加予定です。
        </p>
        <p className="mt-2 text-xs text-gray-500">
          あなたのID:{" "}
          <code className="rounded bg-[#151d2a] px-1.5 py-0.5">
            {userId ?? "未発行（育成データを初めて保存すると発行されます）"}
          </code>
        </p>
      </section>
      </div>
    </ConsumerPage>
  );
}
