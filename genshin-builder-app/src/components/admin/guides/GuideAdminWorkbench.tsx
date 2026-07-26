"use client";

import { useCallback, useMemo, useState } from "react";

type ModuleId =
  | "channels"
  | "videos"
  | "analyze"
  | "recommendations"
  | "conflicts";

interface Overview {
  channels: Array<{
    id: string;
    channelId: string;
    title: string;
    enabled: boolean;
    permissionStatus: string;
    notes: string;
    lastFetchedAt: string | null;
  }>;
  videos: Array<{
    id: string;
    videoId: string;
    channelId: string;
    title: string;
    analysisStatus: string;
    sourceUrl: string;
    channel?: { title: string; permissionStatus: string };
  }>;
  jobs: Array<{
    id: string;
    videoId: string;
    status: string;
    errorCode: string;
    createdAt: string;
  }>;
  recommendations: Array<{
    id: string;
    characterId: string;
    status: string;
    origin: string;
    overallConfidence: number;
    targets: unknown[];
    contributions: Array<{
      id: string;
      videoId: string;
      inclusion: string;
      fieldPath: string;
    }>;
    evidence: Array<{ snippet: string; fieldPath: string; videoId: string }>;
    adminNotes: string;
  }>;
  audits: Array<{ id: number; action: string; status: string; detail: string; createdAt: string }>;
}

const MODULES: Array<{ id: ModuleId; label: string }> = [
  { id: "channels", label: "チャンネル" },
  { id: "videos", label: "動画" },
  { id: "analyze", label: "解析実行" },
  { id: "recommendations", label: "推奨詳細" },
  { id: "conflicts", label: "動画比較・矛盾" },
];

export default function GuideAdminWorkbench() {
  const [secret, setSecret] = useState("");
  const [module, setModule] = useState<ModuleId>("channels");
  const [overview, setOverview] = useState<Overview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [channelId, setChannelId] = useState("");
  const [permissionStatus, setPermissionStatus] = useState("unknown");
  const [selectedVideoId, setSelectedVideoId] = useState("");
  const [transcript, setTranscript] = useState("");
  const [format, setFormat] = useState<"txt" | "vtt" | "srt" | "">("");
  const [mergeCharacterId, setMergeCharacterId] = useState("");
  const [mergeVideoIds, setMergeVideoIds] = useState("");
  const [lastResult, setLastResult] = useState<string>("");

  const authHeaders = useMemo(
    () => ({
      Authorization: `Bearer ${secret}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    }),
    [secret],
  );

  const refresh = useCallback(async () => {
    setBusy(true);
    setError(null);
    try {
      const response = await fetch("/api/admin/build-guides", {
        headers: authHeaders,
        cache: "no-store",
      });
      const body = (await response.json()) as Overview & { error?: string };
      if (!response.ok) {
        setError(body.error ?? `http${response.status}`);
        setOverview(null);
        return;
      }
      setOverview(body);
    } catch {
      setError("networkError");
    } finally {
      setBusy(false);
    }
  }, [authHeaders]);

  const postAction = useCallback(
    async (payload: Record<string, unknown>) => {
      setBusy(true);
      setError(null);
      try {
        const response = await fetch("/api/admin/build-guides", {
          method: "POST",
          headers: authHeaders,
          body: JSON.stringify(payload),
        });
        const body = (await response.json()) as { error?: string };
        if (!response.ok) {
          setError(body.error ?? `http${response.status}`);
          setLastResult(JSON.stringify(body, null, 2));
          return;
        }
        setLastResult(JSON.stringify(body, null, 2));
        await refresh();
      } catch {
        setError("networkError");
      } finally {
        setBusy(false);
      }
    },
    [authHeaders, refresh],
  );

  return (
    <div className="space-y-4">
      <header className="rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
        <h1 className="text-xl font-bold">Build Guide 管理</h1>
        <p className="mt-1 text-sm text-gray-400">
          YouTube メタデータ取得・手動字幕解析・推奨承認/公開。字幕全文はサーバに保存しません。
          公開表現は「動画内推奨目安」です（公式/理想/最適の断定禁止）。
        </p>
        <div className="mt-4 flex flex-col gap-2 sm:flex-row sm:items-end">
          <label className="flex-1 text-sm">
            <span className="text-gray-400">BUILD_GUIDE_ADMIN_SECRET</span>
            <input
              type="password"
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
              value={secret}
              onChange={(event) => setSecret(event.target.value)}
              autoComplete="off"
            />
          </label>
          <button
            type="button"
            disabled={!secret || busy}
            onClick={() => void refresh()}
            className="rounded-lg bg-accent px-4 py-2 text-sm font-medium text-black disabled:opacity-40"
          >
            概要を読込
          </button>
        </div>
        {error ? <p className="mt-2 text-sm text-red-400">エラー: {error}</p> : null}
      </header>

      <nav className="flex flex-wrap gap-2">
        {MODULES.map((item) => (
          <button
            key={item.id}
            type="button"
            onClick={() => setModule(item.id)}
            className={`rounded-lg px-3 py-1.5 text-sm ${
              module === item.id
                ? "bg-accent text-black"
                : "bg-[#1e2a3a] text-gray-200 border border-white/10"
            }`}
          >
            {item.label}
          </button>
        ))}
      </nav>

      {module === "channels" ? (
        <section className="space-y-3 rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
          <h2 className="font-bold">チャンネル登録 / 同期</h2>
          <div className="grid gap-2 sm:grid-cols-2">
            <label className="text-sm">
              Channel ID (UC…)
              <input
                className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
                value={channelId}
                onChange={(e) => setChannelId(e.target.value.trim())}
              />
            </label>
            <label className="text-sm">
              permissionStatus
              <select
                className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
                value={permissionStatus}
                onChange={(e) => setPermissionStatus(e.target.value)}
              >
                <option value="unknown">unknown</option>
                <option value="pending">pending</option>
                <option value="approved_for_processing">approved_for_processing</option>
                <option value="denied">denied</option>
              </select>
            </label>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={!secret || !channelId || busy}
              className="rounded-lg bg-accent px-3 py-2 text-sm text-black disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "registerChannel",
                  channelId,
                  permissionStatus,
                })
              }
            >
              登録/更新
            </button>
            <button
              type="button"
              disabled={!secret || !channelId || busy}
              className="rounded-lg border border-white/20 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({ action: "syncChannelVideos", channelId })
              }
            >
              動画同期
            </button>
            <button
              type="button"
              disabled={!secret || !channelId || busy}
              className="rounded-lg border border-white/20 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "updateChannel",
                  channelId,
                  permissionStatus,
                })
              }
            >
              権限のみ更新
            </button>
          </div>
          <ul className="space-y-2 text-sm">
            {(overview?.channels ?? []).map((channel) => (
              <li
                key={channel.id}
                className="rounded-lg bg-[#151d2a] p-3"
              >
                <div className="font-medium">{channel.title}</div>
                <div className="text-gray-400">
                  {channel.channelId} / {channel.permissionStatus} /{" "}
                  {channel.enabled ? "enabled" : "disabled"}
                </div>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {module === "videos" ? (
        <section className="space-y-3 rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
          <h2 className="font-bold">動画一覧</h2>
          <ul className="max-h-[28rem] space-y-2 overflow-auto text-sm">
            {(overview?.videos ?? []).map((video) => (
              <li key={video.id} className="rounded-lg bg-[#151d2a] p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <div className="font-medium">{video.title}</div>
                    <div className="text-gray-400">
                      {video.videoId} / {video.analysisStatus} /{" "}
                      {video.channel?.title ?? video.channelId}
                    </div>
                  </div>
                  <button
                    type="button"
                    className="rounded border border-white/20 px-2 py-1 text-xs"
                    onClick={() => {
                      setSelectedVideoId(video.videoId);
                      setModule("analyze");
                    }}
                  >
                    解析へ
                  </button>
                </div>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {module === "analyze" ? (
        <section className="space-y-3 rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
          <h2 className="font-bold">字幕貼り付け解析</h2>
          <p className="text-sm text-gray-400">
            TXT / VTT / SRT を手動貼り付け。自動字幕取得・スクレイピングは行いません。
          </p>
          <label className="block text-sm">
            videoId
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
              value={selectedVideoId}
              onChange={(e) => setSelectedVideoId(e.target.value.trim())}
            />
          </label>
          <label className="block text-sm">
            format（空なら自動判定）
            <select
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
              value={format}
              onChange={(e) =>
                setFormat(e.target.value as "txt" | "vtt" | "srt" | "")
              }
            >
              <option value="">auto</option>
              <option value="txt">txt</option>
              <option value="vtt">vtt</option>
              <option value="srt">srt</option>
            </select>
          </label>
          <label className="block text-sm">
            transcript
            <textarea
              className="mt-1 h-48 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2 font-mono text-xs"
              value={transcript}
              onChange={(e) => setTranscript(e.target.value)}
            />
          </label>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={!secret || !selectedVideoId || !transcript || busy}
              className="rounded-lg bg-accent px-3 py-2 text-sm text-black disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "analyzeTranscript",
                  videoId: selectedVideoId,
                  transcript,
                  ...(format ? { format } : {}),
                })
              }
            >
              解析実行
            </button>
            <button
              type="button"
              disabled={!secret || !selectedVideoId || !transcript || busy}
              className="rounded-lg border border-white/20 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "reanalyze",
                  videoId: selectedVideoId,
                  transcript,
                  ...(format ? { format } : {}),
                })
              }
            >
              強制再解析
            </button>
            <button
              type="button"
              disabled={!secret || !selectedVideoId || busy}
              className="rounded-lg border border-red-400/40 px-3 py-2 text-sm text-red-300 disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "deleteTranscriptData",
                  videoId: selectedVideoId,
                })
              }
            >
              解析成果物クリア
            </button>
          </div>
          <div>
            <h3 className="text-sm font-medium text-gray-300">直近 Job</h3>
            <ul className="mt-2 space-y-1 text-xs text-gray-400">
              {(overview?.jobs ?? []).slice(0, 10).map((job) => (
                <li key={job.id}>
                  {job.videoId} · {job.status}
                  {job.errorCode ? ` · ${job.errorCode}` : ""}
                </li>
              ))}
            </ul>
          </div>
        </section>
      ) : null}

      {module === "recommendations" ? (
        <section className="space-y-3 rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
          <h2 className="font-bold">推奨詳細 / 承認・公開</h2>
          <ul className="space-y-3 text-sm">
            {(overview?.recommendations ?? []).map((rec) => (
              <li key={rec.id} className="rounded-lg bg-[#151d2a] p-3">
                <div className="font-medium">
                  {rec.characterId} · {rec.status} · {rec.origin}
                </div>
                <div className="text-gray-400">
                  confidence {rec.overallConfidence.toFixed(2)} · targets{" "}
                  {Array.isArray(rec.targets) ? rec.targets.length : 0}
                </div>
                <div className="mt-2 text-xs text-gray-500">
                  evidence:{" "}
                  {rec.evidence
                    .slice(0, 3)
                    .map((e) => e.snippet)
                    .join(" / ") || "—"}
                </div>
                <div className="mt-2 flex flex-wrap gap-2">
                  <button
                    type="button"
                    className="rounded border border-white/20 px-2 py-1 text-xs"
                    disabled={busy}
                    onClick={() =>
                      void postAction({
                        action: "approveRecommendation",
                        recommendationId: rec.id,
                      })
                    }
                  >
                    承認
                  </button>
                  <button
                    type="button"
                    className="rounded border border-white/20 px-2 py-1 text-xs"
                    disabled={busy}
                    onClick={() =>
                      void postAction({
                        action: "rejectRecommendation",
                        recommendationId: rec.id,
                      })
                    }
                  >
                    却下
                  </button>
                  <button
                    type="button"
                    className="rounded border border-accent/40 px-2 py-1 text-xs"
                    disabled={busy}
                    onClick={() =>
                      void postAction({
                        action: "publishRecommendation",
                        recommendationId: rec.id,
                      })
                    }
                  >
                    公開
                  </button>
                  <button
                    type="button"
                    className="rounded border border-white/20 px-2 py-1 text-xs"
                    disabled={busy}
                    onClick={() =>
                      void postAction({
                        action: "unpublishRecommendation",
                        recommendationId: rec.id,
                      })
                    }
                  >
                    非公開
                  </button>
                </div>
                <div className="mt-2 space-y-1 text-xs text-gray-400">
                  {rec.contributions.map((c) => (
                    <div key={c.id} className="flex flex-wrap items-center gap-2">
                      <span>
                        {c.videoId} · {c.inclusion}
                      </span>
                      <button
                        type="button"
                        className="underline"
                        onClick={() =>
                          void postAction({
                            action: "setContributionInclusion",
                            contributionId: c.id,
                            inclusion:
                              c.inclusion === "included" ? "excluded" : "included",
                          })
                        }
                      >
                        出典トグル
                      </button>
                    </div>
                  ))}
                </div>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {module === "conflicts" ? (
        <section className="space-y-3 rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
          <h2 className="font-bold">複数動画マージ / 矛盾確認</h2>
          <label className="block text-sm">
            characterId
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
              value={mergeCharacterId}
              onChange={(e) => setMergeCharacterId(e.target.value.trim())}
            />
          </label>
          <label className="block text-sm">
            videoIds（カンマ区切り）
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
              value={mergeVideoIds}
              onChange={(e) => setMergeVideoIds(e.target.value)}
            />
          </label>
          <button
            type="button"
            disabled={!secret || !mergeCharacterId || !mergeVideoIds || busy}
            className="rounded-lg bg-accent px-3 py-2 text-sm text-black disabled:opacity-40"
            onClick={() =>
              void postAction({
                action: "mergeRecommendations",
                characterId: mergeCharacterId,
                videoIds: mergeVideoIds
                  .split(",")
                  .map((v) => v.trim())
                  .filter(Boolean),
              })
            }
          >
            統合候補を作成
          </button>
          <p className="text-xs text-gray-400">
            矛盾がある場合は API 応答の conflicts を確認し、推奨詳細で出典除外・override
            後に承認してください。approved_for_processing 以外のチャンネルは公開できません。
          </p>
        </section>
      ) : null}

      {lastResult ? (
        <section className="rounded-xl border border-white/10 bg-[#151d2a] p-4">
          <h2 className="text-sm font-bold text-gray-300">直近レスポンス</h2>
          <pre className="mt-2 max-h-64 overflow-auto whitespace-pre-wrap text-xs text-gray-400">
            {lastResult}
          </pre>
        </section>
      ) : null}

      {(overview?.audits?.length ?? 0) > 0 ? (
        <section className="rounded-xl border border-white/10 bg-[#1e2a3a] p-4">
          <h2 className="text-sm font-bold">監査ログ</h2>
          <ul className="mt-2 max-h-40 space-y-1 overflow-auto text-xs text-gray-400">
            {overview!.audits.map((audit) => (
              <li key={audit.id}>
                {audit.action} · {audit.status} · {audit.detail.slice(0, 120)}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}
