"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

/** ナビゲーションのリンク定義 */
const NAV_LINKS = [
  { href: "/", label: "ホーム" },
  { href: "/characters", label: "キャラクター" },
  { href: "/settings", label: "設定" },
] as const;

/**
 * 共通ヘッダー
 * 現在のパスに応じてアクティブなリンクをハイライトするため Client Component。
 */
export default function Header() {
  const pathname = usePathname();

  /** 現在表示中のページかどうかを判定する */
  const isActive = (href: string) =>
    href === "/" ? pathname === "/" : pathname.startsWith(href);

  return (
    <header className="sticky top-0 z-50 border-b border-white/10 bg-[#151d2a]/90 backdrop-blur">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-3 sm:px-6">
        <Link href="/" className="flex items-center gap-2">
          <span className="text-xl text-accent">✦</span>
          <span className="bg-gradient-to-r from-[#f0c674] to-[#d4a853] bg-clip-text text-lg font-bold text-transparent">
            Genshin Builder
          </span>
        </Link>

        <nav className="flex gap-1" aria-label="メインナビゲーション">
          {NAV_LINKS.map(({ href, label }) => (
            <Link
              key={href}
              href={href}
              className={`rounded-lg px-3 py-1.5 text-sm transition-colors ${
                isActive(href)
                  ? "bg-accent/10 font-medium text-accent"
                  : "text-gray-400 hover:bg-white/5 hover:text-gray-100"
              }`}
            >
              {label}
            </Link>
          ))}
        </nav>
      </div>
    </header>
  );
}
