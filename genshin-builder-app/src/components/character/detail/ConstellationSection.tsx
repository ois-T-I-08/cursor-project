"use client";

import type { ConstellationInfo } from "@/lib/api/amber-details";
import Accordion from "@/components/ui/Accordion";

/**
 * 命ノ星座（凸）セクション（アコーディオン）
 * 概要: 現在の凸数
 * 詳細: 0〜6凸の選択・各凸効果一覧（現在の凸効果を強調表示）
 */
export default function ConstellationSection({
  constellation,
  constellations,
  onChange,
}: {
  constellation: number;
  constellations: ConstellationInfo[];
  onChange: (constellation: number) => void;
}) {
  const summary = (
    <p className="text-sm text-gray-300">
      現在 <span className="font-bold text-accent">{constellation}凸</span>
    </p>
  );

  return (
    <Accordion title="命ノ星座（凸）" summary={summary}>
      <div className="space-y-4">
        {/* 凸数の選択 */}
        <div className="flex flex-wrap gap-2" role="group" aria-label="凸数の選択">
          {[0, 1, 2, 3, 4, 5, 6].map((n) => (
            <button
              key={n}
              type="button"
              onClick={() => onChange(n)}
              aria-pressed={constellation === n}
              className={`rounded-lg px-3 py-1.5 text-sm transition-colors ${
                constellation === n
                  ? "bg-gradient-to-r from-[#d4a853] to-[#b8923f] font-medium text-gray-900"
                  : "border border-white/10 bg-[#151d2a] text-gray-300 hover:border-white/30"
              }`}
            >
              {n}凸
            </button>
          ))}
        </div>

        {/* 凸効果一覧 */}
        {constellations.length > 0 ? (
          <ol className="space-y-2">
            {constellations.map((c) => {
              const active = c.position <= constellation;
              return (
                <li
                  key={c.position}
                  className={`rounded-lg p-3 transition-colors ${
                    active
                      ? "border border-accent/40 bg-accent/5"
                      : "bg-[#151d2a] opacity-60"
                  }`}
                >
                  <h3 className="text-sm font-bold">
                    <span className={active ? "text-accent" : "text-gray-500"}>
                      第{c.position}重
                    </span>{" "}
                    {c.name}
                    {active && (
                      <span className="ml-2 rounded-full bg-accent/15 px-2 py-0.5 text-xs font-medium text-accent">
                        解放済み
                      </span>
                    )}
                  </h3>
                  <p className="mt-1 whitespace-pre-line text-xs leading-relaxed text-gray-300">
                    {c.description}
                  </p>
                </li>
              );
            })}
          </ol>
        ) : (
          <p className="text-sm text-gray-500">
            凸効果の情報を取得できませんでした。
          </p>
        )}
      </div>
    </Accordion>
  );
}
