import type { Metadata } from "next";
import Link from "next/link";
import ConsumerPage from "@/components/consumer/ConsumerPage";

export const metadata: Metadata = { title: "その他" };

export default function MorePage() {
  return (
    <ConsumerPage
      title="その他"
      description="設定やデータ管理など、日々の育成以外の項目をまとめています。"
    >
      <section className="consumer-card divide-y divide-app-border overflow-hidden">
        <Link
          href="/settings"
          className="flex min-h-14 items-center justify-between gap-4 px-5 py-3 font-bold"
        >
          <span>設定とデータ同期</span>
          <span aria-hidden="true">→</span>
        </Link>
        <div className="px-5 py-4">
          <h2 className="font-bold">このWebアプリについて</h2>
          <p className="consumer-muted mt-1 text-sm leading-6">
            原神の育成状況を整理する非公式のファンメイドツールです。アカウント連携とモバイル版との同期は現在提供していません。
          </p>
        </div>
      </section>
    </ConsumerPage>
  );
}
