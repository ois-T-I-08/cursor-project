"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import type { WeaponOption } from "@/lib/repository/weapons";

const triggerClass =
  "flex w-full items-center gap-2 rounded-lg border border-white/10 bg-[#151d2a] px-2 py-1.5 text-left text-sm text-gray-200 transition-colors hover:border-white/25 focus:border-accent focus:outline-none";

/**
 * 武器選択ピッカー（アイコン付き）
 * 通常の select ではアイコンを表示できないため、カスタムドロップダウンで実装。
 */
export default function WeaponPicker({
  weapons,
  value,
  onChange,
  id = "weapon-select",
}: {
  weapons: WeaponOption[];
  value: string;
  onChange: (weaponId: string) => void;
  id?: string;
}) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const containerRef = useRef<HTMLDivElement>(null);

  const selected = weapons.find((w) => w.id === value) ?? null;

  const filtered = weapons.filter((w) =>
    search ? w.name.includes(search) : true,
  );

  // 外側クリックで閉じる
  useEffect(() => {
    if (!open) return;
    function handleClick(e: MouseEvent) {
      if (
        containerRef.current &&
        !containerRef.current.contains(e.target as Node)
      ) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [open]);

  function pick(weaponId: string) {
    onChange(weaponId);
    setOpen(false);
    setSearch("");
  }

  return (
    <div ref={containerRef} className="relative">
      <button
        type="button"
        id={id}
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className={triggerClass}
      >
        {selected ? (
          <>
            <Image
              src={selected.iconUrl}
              alt=""
              width={28}
              height={28}
              className="shrink-0 rounded bg-[#1e2a3a]"
              unoptimized
            />
            <span className="min-w-0 flex-1 truncate">
              <span className="text-amber-400/80">
                {"★".repeat(selected.rarity)}{" "}
              </span>
              {selected.name}
            </span>
          </>
        ) : (
          <span className="text-gray-500">武器を選択...</span>
        )}
        <span aria-hidden className="shrink-0 text-xs text-gray-500">
          {open ? "▲" : "▼"}
        </span>
      </button>

      {open && (
        <div className="absolute z-20 mt-1 w-full overflow-hidden rounded-lg border border-white/15 bg-[#1e2a3a] shadow-lg">
          <div className="border-b border-white/10 p-2">
            <input
              type="search"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="武器名で検索..."
              className="w-full rounded-md border border-white/10 bg-[#151d2a] px-2 py-1.5 text-sm text-gray-200 focus:border-accent focus:outline-none"
              autoFocus
            />
          </div>

          <ul
            role="listbox"
            aria-label="武器一覧"
            className="max-h-56 overflow-y-auto p-1"
          >
            <li>
              <button
                type="button"
                role="option"
                aria-selected={value === ""}
                onClick={() => pick("")}
                className={`flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm transition-colors hover:bg-white/5 ${
                  value === "" ? "bg-accent/10 text-accent" : "text-gray-400"
                }`}
              >
                未設定
              </button>
            </li>
            {filtered.map((w) => (
              <li key={w.id}>
                <button
                  type="button"
                  role="option"
                  aria-selected={value === w.id}
                  onClick={() => pick(w.id)}
                  className={`flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm transition-colors hover:bg-white/5 ${
                    value === w.id ? "bg-accent/10" : ""
                  }`}
                >
                  <Image
                    src={w.iconUrl}
                    alt=""
                    width={32}
                    height={32}
                    className="shrink-0 rounded bg-[#151d2a]"
                    unoptimized
                  />
                  <span className="min-w-0 flex-1 truncate">
                    <span className="text-amber-400/80">
                      {"★".repeat(w.rarity)}{" "}
                    </span>
                    {w.name}
                  </span>
                </button>
              </li>
            ))}
            {filtered.length === 0 && (
              <li className="px-2 py-3 text-center text-xs text-gray-500">
                該当する武器がありません
              </li>
            )}
          </ul>
        </div>
      )}
    </div>
  );
}
