"use client";

import { useState, type ReactNode } from "react";

/**
 * アコーディオン（開閉パネル）
 * 閉じた状態では summary（概要）のみ、開くと children（詳細）を表示する。
 */
export default function Accordion({
  title,
  summary,
  children,
  defaultOpen = false,
}: {
  /** セクション名（例: "武器"） */
  title: string;
  /** 閉じた状態でも表示する概要 */
  summary: ReactNode;
  /** 開いたときに表示する詳細 */
  children: ReactNode;
  defaultOpen?: boolean;
}) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <section className="overflow-hidden rounded-xl border border-white/10 bg-[#1e2a3a]">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        className="flex w-full items-center gap-3 p-4 text-left transition-colors hover:bg-white/5"
      >
        <div className="min-w-0 flex-1">
          <h2 className="text-sm font-bold text-accent">{title}</h2>
          <div className="mt-1">{summary}</div>
        </div>
        <span
          aria-hidden
          className={`shrink-0 text-gray-500 transition-transform ${open ? "rotate-180" : ""}`}
        >
          ▼
        </span>
      </button>

      {open && (
        <div className="border-t border-white/10 p-4">{children}</div>
      )}
    </section>
  );
}
