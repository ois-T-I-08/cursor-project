"use client";

import { useCallback, useMemo, useState } from "react";

type ModuleId = "channels" | "videos" | "evidence" | "recommendations" | "merge";

interface Overview {
  channels: Array<{
    id: string;
    channelId: string;
    title: string;
    enabled: boolean;
    permissionStatus: string;
    lastFetchedAt: string | null;
    dailyAnalysisLimit: number;
  }>;
  videos: Array<{
    id: string;
    videoId: string;
    channelId: string;
    title: string;
    analysisStatus: string;
    durationSeconds: number | null;
    privacyStatus: string;
    thumbnailUrl: string;
    sourceUrl: string;
    lastAnalyzedAt: string | null;
    channel?: { title: string; permissionStatus: string };
  }>;
  jobs: Array<{
    id: string;
    videoId: string;
    status: string;
    errorCode: string;
    tokenUsage: string;
    createdAt: string;
  }>;
  evidences: Array<{
    id: string;
    videoId: string;
    startSeconds: number;
    endSeconds: number;
    evidenceType: string;
    exactVisibleText: string;
    confidence: number;
    validationStatus: string;
    approvalStatus: string;
    exclusionCode: string;
    purposeSummary: string;
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
      startSeconds: number;
      endSeconds: number;
      exactVisibleText: string;
      contributionRole: string;
      decision: string;
    }>;
    adminNotes: string;
  }>;
  audits: Array<{ id: number; action: string; status: string; detail: string }>;
}

const MODULES: Array<{ id: ModuleId; label: string }> = [
  { id: "channels", label: "チャンネル" },
  { id: "videos", label: "動画" },
  { id: "evidence", label: "映像証拠" },
  { id: "recommendations", label: "推奨詳細" },
  { id: "merge", label: "統合・矛盾" },
];

function formatTime(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

export default function GuideAdminWorkbench() {
  const [secret, setSecret] = useState("");
  const [module, setModule] = useState<ModuleId>("channels");
  const [overview, setOverview] = useState<Overview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [channelId, setChannelId] = useState("");
  const [permissionStatus, setPermissionStatus] = useState("unknown");
  const [selectedVideoId, setSelectedVideoId] = useState("");
  const [rangeStart, setRangeStart] = useState("0");
  const [rangeEnd, setRangeEnd] = useState("60");
  const [mergeCharacterId, setMergeCharacterId] = useState("");
  const [mergeEvidenceIds, setMergeEvidenceIds] = useState("");
  const [lastResult, setLastResult] = useState("");

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

  const evidencesForVideo = (overview?.evidences ?? []).filter(
    (e) => !selectedVideoId || e.videoId === selectedVideoId,
  );

  return (
    <div className="space-y-4">
      <header className="rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
        <h1 className="text-xl font-bold">Build Guide 管理（映像OCR）</h1>
        <p className="mt-1 text-sm text-gray-400">
          YouTube Data API はメタデータ同期のみ。推奨値は Gemini による画面内文字/表の認識結果を、通常コード検証と管理者承認後に公開します。
          動画本体はダウンロード・保存しません。
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
                : "border border-white/10 bg-[#1e2a3a] text-gray-200"
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
              onClick={() => void postAction({ action: "syncChannelVideos", channelId })}
            >
              動画同期
            </button>
          </div>
          <ul className="space-y-2 text-sm">
            {(overview?.channels ?? []).map((channel) => (
              <li key={channel.id} className="rounded-lg bg-[#151d2a] p-3">
                <div className="font-medium">{channel.title}</div>
                <div className="text-gray-400">
                  {channel.channelId} / {channel.permissionStatus} / 日次上限{" "}
                  {channel.dailyAnalysisLimit}
                </div>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {module === "videos" ? (
        <section className="space-y-3 rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
          <h2 className="font-bold">動画一覧 / 映像解析</h2>
          <label className="block text-sm">
            videoId
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
              value={selectedVideoId}
              onChange={(e) => setSelectedVideoId(e.target.value.trim())}
            />
          </label>
          <div className="grid gap-2 sm:grid-cols-2">
            <label className="text-sm">
              range start (sec)
              <input
                className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
                value={rangeStart}
                onChange={(e) => setRangeStart(e.target.value)}
              />
            </label>
            <label className="text-sm">
              range end (sec)
              <input
                className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
                value={rangeEnd}
                onChange={(e) => setRangeEnd(e.target.value)}
              />
            </label>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={!secret || !selectedVideoId || busy}
              className="rounded-lg bg-accent px-3 py-2 text-sm text-black disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "analyzeVideoVisuals",
                  videoId: selectedVideoId,
                })
              }
            >
              映像解析
            </button>
            <button
              type="button"
              disabled={!secret || !selectedVideoId || busy}
              className="rounded-lg border border-white/20 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "reanalyzeVideoVisuals",
                  videoId: selectedVideoId,
                })
              }
            >
              強制再解析
            </button>
            <button
              type="button"
              disabled={!secret || !selectedVideoId || busy}
              className="rounded-lg border border-white/20 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "analyzeSelectedRanges",
                  videoId: selectedVideoId,
                  ranges: [
                    {
                      startSeconds: Number(rangeStart) || 0,
                      endSeconds: Number(rangeEnd) || 0,
                      reason: "admin-selected",
                    },
                  ],
                })
              }
            >
              指定時間帯を解析
            </button>
          </div>
          <ul className="max-h-[28rem] space-y-2 overflow-auto text-sm">
            {(overview?.videos ?? []).map((video) => (
              <li key={video.id} className="rounded-lg bg-[#151d2a] p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <div className="font-medium">{video.title}</div>
                    <div className="text-gray-400">
                      {video.videoId} · {video.privacyStatus} ·{" "}
                      {video.durationSeconds != null
                        ? formatTime(video.durationSeconds)
                        : "?:??"}{" "}
                      · {video.analysisStatus}
                    </div>
                  </div>
                  <button
                    type="button"
                    className="rounded border border-white/20 px-2 py-1 text-xs"
                    onClick={() => {
                      setSelectedVideoId(video.videoId);
                      setModule("evidence");
                    }}
                  >
                    証拠へ
                  </button>
                </div>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {module === "evidence" ? (
        <section className="space-y-3 rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
          <h2 className="font-bold">映像証拠タイムライン</h2>
          <p className="text-sm text-gray-400">
            選択 videoId: {selectedVideoId || "（全件）"}
          </p>
          <ul className="space-y-2 text-sm">
            {evidencesForVideo.map((evidence) => (
              <li key={evidence.id} className="rounded-lg bg-[#151d2a] p-3">
                <div className="font-medium">
                  {formatTime(evidence.startSeconds)} {evidence.evidenceType}
                </div>
                <div className="text-gray-300">
                  画面表示「{evidence.exactVisibleText}」
                </div>
                <div className="text-xs text-gray-500">
                  conf {evidence.confidence.toFixed(2)} · {evidence.validationStatus} ·{" "}
                  {evidence.approvalStatus}
                  {evidence.exclusionCode ? ` · ${evidence.exclusionCode}` : ""}
                  {evidence.purposeSummary ? ` · ${evidence.purposeSummary}` : ""}
                </div>
                <div className="mt-2 flex flex-wrap gap-2">
                  <a
                    className="rounded border border-white/20 px-2 py-1 text-xs underline"
                    href={`https://www.youtube.com/watch?v=${evidence.videoId}&t=${Math.floor(evidence.startSeconds)}s`}
                    target="_blank"
                    rel="noreferrer"
                  >
                    YouTubeで該当時刻
                  </a>
                  <button
                    type="button"
                    className="rounded border border-white/20 px-2 py-1 text-xs"
                    disabled={busy}
                    onClick={() =>
                      void postAction({
                        action: "approveVisualEvidence",
                        evidenceId: evidence.id,
                      })
                    }
                  >
                    採用
                  </button>
                  <button
                    type="button"
                    className="rounded border border-white/20 px-2 py-1 text-xs"
                    disabled={busy}
                    onClick={() =>
                      void postAction({
                        action: "rejectVisualEvidence",
                        evidenceId: evidence.id,
                        exclusionCode: "adminRejected",
                      })
                    }
                  >
                    却下
                  </button>
                </div>
              </li>
            ))}
          </ul>
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
                <div className="mt-2 space-y-1 text-xs text-gray-400">
                  {rec.contributions.map((c) => (
                    <div key={c.id}>
                      {c.contributionRole}: {c.videoId} {formatTime(c.startSeconds)} 「
                      {c.exactVisibleText}」 ({c.decision})
                    </div>
                  ))}
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
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {module === "merge" ? (
        <section className="space-y-3 rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
          <h2 className="font-bold">複数証拠の統合</h2>
          <label className="block text-sm">
            characterId
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
              value={mergeCharacterId}
              onChange={(e) => setMergeCharacterId(e.target.value.trim())}
            />
          </label>
          <label className="block text-sm">
            evidenceIds（カンマ区切り）
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
              value={mergeEvidenceIds}
              onChange={(e) => setMergeEvidenceIds(e.target.value)}
            />
          </label>
          <button
            type="button"
            disabled={!secret || !mergeCharacterId || !mergeEvidenceIds || busy}
            className="rounded-lg bg-accent px-3 py-2 text-sm text-black disabled:opacity-40"
            onClick={() =>
              void postAction({
                action: "mergeVisualRecommendations",
                characterId: mergeCharacterId,
                evidenceIds: mergeEvidenceIds
                  .split(",")
                  .map((v) => v.trim())
                  .filter(Boolean),
              })
            }
          >
            統合候補を作成
          </button>
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

      {(overview?.jobs?.length ?? 0) > 0 ? (
        <section className="rounded-xl border border-white/10 bg-[#1e2a3a] p-4">
          <h2 className="text-sm font-bold">解析 Job / usage</h2>
          <ul className="mt-2 max-h-40 space-y-1 overflow-auto text-xs text-gray-400">
            {overview!.jobs.map((job) => (
              <li key={job.id}>
                {job.videoId} · {job.status}
                {job.errorCode ? ` · ${job.errorCode}` : ""}
                {job.tokenUsage ? ` · usage ${job.tokenUsage.slice(0, 80)}` : ""}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}
