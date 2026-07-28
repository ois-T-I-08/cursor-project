"use client";

import { useCallback, useMemo, useState } from "react";
import StructuredRecommendationEditor from "./StructuredRecommendationEditor";
import {
  GENSIN_VIDEO_TITLE_MARKER,
  isGenshinTitledVideo,
} from "@/lib/build-guides/genshin-video-title";

type ModuleId =
  | "channels"
  | "videos"
  | "evidence"
  | "recommendations"
  | "structured"
  | "merge";

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
    publishedAt: string | null;
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
    weaponMentions?: unknown[];
    artifactSetMentions?: unknown[];
  }>;
  recommendations: Array<{
    id: string;
    characterId: string;
    status: string;
    origin: string;
    overallConfidence: number;
    targets: unknown[];
    mainStats?: unknown[];
    substatPriority?: unknown[];
    context?: Record<string, unknown>;
    structuredPayload?: Record<string, unknown>;
    structuredReviewStatus?: string | null;
    hasUnpublishedDraft?: boolean;
    pendingMentions?: { weapons?: unknown[]; artifactSets?: unknown[] };
    updatedAt?: string;
    publishedAt?: string | null;
    lastVerifiedAt?: string | null;
    contributions: Array<{
      id: string;
      videoId: string;
      startSeconds: number;
      endSeconds: number;
      exactVisibleText: string;
      contributionRole: string;
      decision: string;
      videoTitle?: string;
      channelTitle?: string;
      sourceUrl?: string;
    }>;
    revisions?: Array<{
      id: string;
      action: string;
      actor: string;
      createdAt: string;
      beforePayload: string;
      afterPayload: string;
    }>;
    adminNotes: string;
  }>;
  audits: Array<{ id: number; action: string; status: string; detail: string }>;
  geminiCost?: {
    primaryModel: string;
    discoveryFps: number;
    detailFps: number;
    maxDetailFps: number;
    estimatedDetailCostMultiplier: number;
    note: string;
  };
}

const MODULES: Array<{ id: ModuleId; label: string }> = [
  { id: "channels", label: "チャンネル" },
  { id: "videos", label: "動画" },
  { id: "evidence", label: "映像証拠" },
  { id: "recommendations", label: "推奨詳細" },
  { id: "structured", label: "構造化編集" },
  { id: "merge", label: "統合・矛盾" },
];

function formatAdminError(error: string | undefined, status?: number): string {
  if (error === "rateLimited" || status === 429) {
    return "操作が多すぎます。約1分待ってから再試行してください。";
  }
  return error ?? (status ? `http${status}` : "error");
}

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
  const [playlistId, setPlaylistId] = useState("");
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
        setError(formatAdminError(body.error, response.status));
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
        const body = (await response.json()) as { error?: string; detail?: string };
        setLastResult(JSON.stringify(body, null, 2));
        if (!response.ok) {
          setError(
            body.detail
              ? `${formatAdminError(body.error, response.status)}: ${body.detail}`
              : formatAdminError(body.error, response.status),
          );
          return body;
        }
        const skipRefresh =
          payload.action === "listGuideMasterOptions" ||
          payload.action === "previewRecommendationPublic" ||
          payload.action === "validateStructuredRecommendation";
        if (!skipRefresh) {
          await refresh();
        }
        return body;
      } catch {
        setError("networkError");
        return { error: "networkError" };
      } finally {
        setBusy(false);
      }
    },
    [authHeaders, refresh],
  );

  const runAllUncoveredCharacters = useCallback(async () => {
    setBusy(true);
    setError(null);
    const aggregate: unknown[] = [];
    let rounds = 0;
    let totalSucceeded = 0;
    let totalFailed = 0;
    try {
      while (rounds < 80) {
        rounds += 1;
        setLastResult(
          JSON.stringify(
            {
              status: "running",
              round: rounds,
              totalSucceeded,
              totalFailed,
              note: "未カバーキャラを解析中…（ブラウザを閉じないでください）",
            },
            null,
            2,
          ),
        );
        const response = await fetch("/api/admin/build-guides", {
          method: "POST",
          headers: authHeaders,
          body: JSON.stringify({
            action: "analyzePendingGenshinVideos",
            mode: "uncoveredCharacters",
            limit: 3,
            raiseDailyLimitTo: 300,
          }),
        });
        const body = (await response.json()) as {
          error?: string;
          detail?: string;
          attempted?: number;
          succeeded?: number;
          failed?: number;
          remainingUncoveredEstimate?: number | null;
          results?: Array<{ ok: boolean; error?: string }>;
        };
        aggregate.push(body);
        if (!response.ok) {
          setError(
            body.detail
              ? `${formatAdminError(body.error, response.status)}: ${body.detail}`
              : formatAdminError(body.error, response.status),
          );
          break;
        }
        totalSucceeded += body.succeeded ?? 0;
        totalFailed += body.failed ?? 0;
        const hitLimit = (body.results ?? []).some(
          (r) => r.error === "channelDailyLimit",
        );
        const noMore = (body.attempted ?? 0) === 0;
        if (hitLimit || noMore) break;
      }
      setLastResult(
        JSON.stringify(
          {
            status: "done",
            rounds,
            totalSucceeded,
            totalFailed,
            batches: aggregate,
          },
          null,
          2,
        ),
      );
      await refresh();
    } catch {
      setError("networkError");
    } finally {
      setBusy(false);
    }
  }, [authHeaders, refresh]);

  const evidencesForVideo = (overview?.evidences ?? []).filter(
    (e) => !selectedVideoId || e.videoId === selectedVideoId,
  );

  const genshinVideos = useMemo(
    () => (overview?.videos ?? []).filter((video) => isGenshinTitledVideo(video.title)),
    [overview?.videos],
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
              投稿一覧を同期
            </button>
          </div>

          <div className="mt-4 space-y-2 rounded-lg border border-white/10 p-3">
            <h3 className="text-sm font-bold">特定プレイリストから同期</h3>
            <p className="text-xs text-gray-400">
              プレイリスト URL または ID（例: PLxxxx）を指定します。含まれる動画のうち、
              すでに登録済みかつ「approved_for_processing」のチャンネルの動画だけを取り込みます。
              映像解析・承認・公開は自動では行いません。
            </p>
            <label className="block text-sm">
              Playlist URL / ID
              <input
                className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
                value={playlistId}
                onChange={(e) => setPlaylistId(e.target.value.trim())}
                placeholder="https://www.youtube.com/playlist?list=PLxxxx または PLxxxx"
              />
            </label>
            <button
              type="button"
              disabled={!secret || !playlistId || busy}
              className="rounded-lg border border-accent/40 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "syncPlaylistVideos",
                  playlistId,
                })
              }
            >
              プレイリスト同期
            </button>
            <p className="text-xs text-gray-500 sm:col-span-2">
              タイトルに「{GENSIN_VIDEO_TITLE_MARKER}」を含む動画のみ取り込みます（解析は自動実行しません）
            </p>
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
          <p className="text-sm text-gray-400">
            タイトルに「{GENSIN_VIDEO_TITLE_MARKER}」を含む動画のみ表示（公開日が新しい順・最大200件 /{" "}
            {genshinVideos.length} 件）
          </p>
          {overview?.geminiCost ? (
            <p className="rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-100">
              コスト目安: {overview.geminiCost.note} 主モデル{" "}
              {overview.geminiCost.primaryModel}。詳細解析は一次探索の約{" "}
              {overview.geminiCost.estimatedDetailCostMultiplier}{" "}
              倍のフレーム量になります。
            </p>
          ) : null}
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
              disabled={!secret || busy}
              className="rounded-lg bg-accent px-3 py-2 text-sm font-medium text-black disabled:opacity-40"
              onClick={() => void runAllUncoveredCharacters()}
            >
              全キャラ解析（未カバー優先・自動連続）
            </button>
            <button
              type="button"
              disabled={!secret || busy}
              className="rounded-lg border border-accent/50 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "analyzePendingGenshinVideos",
                  mode: "uncoveredCharacters",
                  limit: 3,
                  raiseDailyLimitTo: 300,
                })
              }
            >
              未カバーを3件だけ
            </button>
            <button
              type="button"
              disabled={!secret || busy}
              className="rounded-lg border border-white/20 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "analyzePendingGenshinVideos",
                  limit: 1,
                })
              }
            >
              最新の未解析を1件解析
            </button>
            <button
              type="button"
              disabled={!secret || busy}
              className="rounded-lg border border-white/20 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "analyzePendingGenshinVideos",
                  limit: 3,
                })
              }
            >
              最新の未解析を3件解析
            </button>
            <button
              type="button"
              disabled={!secret || !selectedVideoId || busy}
              className="rounded-lg border border-white/20 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "analyzeVideoVisuals",
                  videoId: selectedVideoId,
                })
              }
            >
              選択動画を解析（全体・低FPS）
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
              強制再解析（全体）
            </button>
            <button
              type="button"
              disabled={!secret || !selectedVideoId || busy}
              className="rounded-lg border border-amber-400/40 px-3 py-2 text-sm disabled:opacity-40"
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
              指定時間帯を詳細解析（高FPS・コスト増）
            </button>
          </div>
          <p className="text-xs text-gray-500">
            「全キャラ解析」は育成ガイド寄りの未解析動画から、まだ推奨のないキャラを1人1本ずつ解析します（目安50〜60本・数時間・Gemini費用あり）。日次上限は自動で300まで引き上げます。成功すると証拠と推奨ドラフトが作成され、公開には承認と構造化 publish が必要です。
          </p>
          <ul className="max-h-[28rem] space-y-2 overflow-auto text-sm">
            {genshinVideos.map((video) => (
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
                      {video.publishedAt
                        ? ` · 公開 ${new Date(video.publishedAt).toLocaleDateString("ja-JP")}`
                        : ""}
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
            {genshinVideos.length === 0 ? (
              <li className="text-sm text-gray-500">
                「{GENSIN_VIDEO_TITLE_MARKER}」付きの動画がありません
              </li>
            ) : null}
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
                {(evidence.weaponMentions?.length ||
                  evidence.artifactSetMentions?.length) ? (
                  <div className="mt-1 text-xs text-amber-200/90">
                    mentions: 武器 {evidence.weaponMentions?.length ?? 0} / 聖遺物{" "}
                    {evidence.artifactSetMentions?.length ?? 0}
                    （信頼度は抽出確度であり育成優先度ではありません）
                  </div>
                ) : null}
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

      {module === "structured" ? (
        <StructuredRecommendationEditor
          recommendations={(overview?.recommendations ?? []).map((r) => ({
            id: r.id,
            characterId: r.characterId,
            status: r.status,
            origin: r.origin,
            overallConfidence: r.overallConfidence,
            updatedAt: r.updatedAt
              ? String(r.updatedAt)
              : new Date().toISOString(),
            publishedAt: r.publishedAt ? String(r.publishedAt) : null,
            lastVerifiedAt: r.lastVerifiedAt ? String(r.lastVerifiedAt) : null,
            adminNotes: r.adminNotes,
            context: r.context ?? {},
            mainStats: r.mainStats ?? [],
            targets: r.targets ?? [],
            substatPriority: r.substatPriority ?? [],
            structuredPayload: r.structuredPayload ?? {},
            structuredReviewStatus: r.structuredReviewStatus ?? null,
            hasUnpublishedDraft: r.hasUnpublishedDraft ?? false,
            pendingMentions: r.pendingMentions ?? { weapons: [], artifactSets: [] },
            contributions: r.contributions,
            revisions: (r.revisions ?? []).map((rev) => ({
              ...rev,
              createdAt:
                typeof rev.createdAt === "string"
                  ? rev.createdAt
                  : String(rev.createdAt),
            })),
          }))}
          busy={busy || !secret}
          postAction={postAction}
        />
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
                        expectedUpdatedAt: rec.updatedAt,
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
                        expectedUpdatedAt: rec.updatedAt,
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
                        expectedUpdatedAt: rec.updatedAt,
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
                        expectedUpdatedAt: rec.updatedAt,
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
