"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type SyncState =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "done"; message: string }
  | { status: "error"; message: string };

/**
 * マスターデータ同期ボタン（Client Component）
 * POST /api/sync を呼び出し、外部APIからDBへゲームデータを取り込む。
 */
export default function SyncButton() {
  const [state, setState] = useState<SyncState>({ status: "idle" });
  const router = useRouter();

  async function handleSync() {
    setState({ status: "loading" });
    try {
      const res = await fetch("/api/sync", { method: "POST" });
      const data: {
        ok: boolean;
        characters?: number;
        weapons?: number;
        materials?: number;
        errors?: string[];
        message?: string;
      } = await res.json();

      if (!res.ok || !data.ok) {
        const detail =
          data.errors?.join(" / ") ?? data.message ?? "不明なエラー";
        setState({ status: "error", message: `同期に失敗しました: ${detail}` });
        return;
      }

      setState({
        status: "done",
        message: `同期完了：キャラクター ${data.characters}件 / 武器 ${data.weapons}件 / 素材 ${data.materials}件`,
      });
      // サーバーコンポーネントの表示（件数・一覧）を最新化する
      router.refresh();
    } catch {
      setState({
        status: "error",
        message: "同期に失敗しました。ネットワーク接続を確認してください。",
      });
    }
  }

  return (
    <div className="space-y-2">
      <button
        onClick={handleSync}
        disabled={state.status === "loading"}
        className="rounded-lg bg-gradient-to-r from-[#d4a853] to-[#b8923f] px-5 py-2 text-sm font-medium text-gray-900 transition-transform hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {state.status === "loading" ? "同期中...（30秒ほどかかります）" : "ゲームデータを同期"}
      </button>

      {state.status === "done" && (
        <p className="text-sm text-emerald-400">{state.message}</p>
      )}
      {state.status === "error" && (
        <p className="text-sm text-red-400">{state.message}</p>
      )}
    </div>
  );
}
