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
  | "merge"
  | "automation";

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
  coverage?: {
    coverageRule: string;
    totalCharacters: number;
    coveredCharacters: number;
    uncoveredCharacters: number;
    publishedCharacters: number;
    pendingReviewCharacters: number;
    evidenceOnlyCharacters: number;
    recoverablePostProcessFailures: number;
    eligiblePendingVideos: number;
    remainingEligibleVideos: number;
    titleResolutionFailedVideos: number;
  };
  automation?: {
    flags: {
      enabled: boolean;
      guideEnabled: boolean;
      discoveryEnabled: boolean;
      transcriptEnabled: boolean;
      analysisEnabled: boolean;
      geminiAnalysisEnabled: boolean;
      deepseekAnalysisEnabled: boolean;
      autoPublishEnabled: boolean;
      maintenanceEnabled: boolean;
    };
    control: {
      emergencyStopped: boolean;
      reason: string;
      version: number;
      updatedAt: string | null;
    };
    runs: Array<{
      id: string;
      pipelineRunId: string;
      trigger: string;
      mode: string;
      status: string;
      dryRun: boolean;
      policyVersion: string;
      startedAt: string;
      completedAt: string | null;
    }>;
    items: Array<{
      id: string;
      videoId: string;
      status: string;
      attempts: number;
      maxAttempts: number;
      nextRetryAt: string | null;
      blockCode: string;
      safeErrorCode: string;
      updatedAt: string;
    }>;
    circuits: Array<{
      providerId: string;
      state: string;
      failureCount: number;
      lastErrorCode: string;
      openUntil: string | null;
    }>;
    leases: Array<{
      lockKey: string;
      leaseOwner: string;
      leaseExpiresAt: string;
      leaseVersion: number;
    }>;
  };
  geminiCost?: {
    primaryModel: string;
    discoveryFps: number;
    detailFps: number;
    maxDetailFps: number;
    estimatedDetailCostMultiplier: number;
    note: string;
  };
  visualAutoPublishEnabled?: boolean;
  buildProvenance?: {
    commitSha: string;
    builtAt: string;
    runtime: "LOCAL" | "VERCEL";
    environment: string;
    appVersion: string | null;
  };
}

const MODULES: Array<{ id: ModuleId; label: string }> = [
  { id: "channels", label: "チャンネル" },
  { id: "videos", label: "動画" },
  { id: "evidence", label: "映像証拠" },
  { id: "recommendations", label: "推奨詳細" },
  { id: "structured", label: "構造化編集" },
  { id: "merge", label: "統合・矛盾" },
  { id: "automation", label: "自動化監視" },
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
  const [limitedBatchVideoIds, setLimitedBatchVideoIds] = useState("");
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
          remainingEligibleVideos?: number | null;
          coverage?: Overview["coverage"];
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
        const abortCodes = new Set([
          "channelDailyLimit",
          "http429",
          "providerRateLimited",
          "geminiProviderCoolingDown",
          "emergencyStopped",
          "EMERGENCY_STOPPED",
          "geminiDisabled",
          "geminiVideoDisabled",
          "geminiNotConfigured",
        ]);
        const hitAbort = (body.results ?? []).some(
          (r) => r.error != null && abortCodes.has(r.error),
        );
        // AI queue empty → stop. postProcess recovery is a separate action (no Gemini).
        const noMore = (body.attempted ?? 0) === 0;
        if (hitAbort || noMore) break;
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
        {overview?.buildProvenance ? (
          <p className="mt-2 font-mono text-[11px] text-gray-500">
            build {overview.buildProvenance.runtime} ·{" "}
            {overview.buildProvenance.environment} · sha{" "}
            {overview.buildProvenance.commitSha.slice(0, 12)}
            {overview.buildProvenance.commitSha.length > 12 ? "…" : ""} · builtAt{" "}
            {overview.buildProvenance.builtAt}
          </p>
        ) : null}
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
          {overview?.coverage ? (
            <div className="rounded-lg border border-white/10 bg-[#151d2a] px-3 py-3 text-xs text-gray-300 space-y-1">
              <div className="font-medium text-sm text-white">Coverage（covered = 推奨 status ≠ rejected）</div>
              <div>
                master {overview.coverage.totalCharacters} · covered{" "}
                {overview.coverage.coveredCharacters} · uncovered{" "}
                {overview.coverage.uncoveredCharacters} · published{" "}
                {overview.coverage.publishedCharacters} · pending_review{" "}
                {overview.coverage.pendingReviewCharacters}
              </div>
              <div>
                evidence-only {overview.coverage.evidenceOnlyCharacters} ·
                title解決失敗 {overview.coverage.titleResolutionFailedVideos} ·
                AI対象 eligible {overview.coverage.eligiblePendingVideos}（残り{" "}
                {overview.coverage.remainingEligibleVideos}）· postProcess復旧{" "}
                {overview.coverage.recoverablePostProcessFailures}
              </div>
              <p className="text-gray-500">
                remainingEligible はキュー残数です。master uncovered と混同しないでください。analyzed +
                postProcess失敗は AI キューから外れ、下の復旧ボタンで Gemini なし復旧します。
              </p>
            </div>
          ) : null}
          <div className="rounded-lg border border-emerald-500/30 bg-emerald-500/5 px-3 py-3 text-xs text-gray-300 space-y-1">
            <div className="font-medium text-sm text-emerald-100">
              自動公開（通常運用）
            </div>
            <p>
              通常: Production 解析成功後に自動公開（Canary / Limited Batch は
              skipAutoPublish で除外）。
            </p>
            <ul className="list-disc pl-4 space-y-0.5 text-gray-400">
              <li>
                visual env (BUILD_GUIDE_VISUAL_AUTO_PUBLISH):{" "}
                {overview?.visualAutoPublishEnabled ? "ON" : "OFF"}
              </li>
              <li>
                automation master:{" "}
                {overview?.automation?.flags?.enabled ? "ON" : "OFF"} ·
                autoPublish flag:{" "}
                {overview?.automation?.flags?.autoPublishEnabled ? "ON" : "OFF"}
              </li>
              <li>
                Emergency:{" "}
                {overview?.automation?.control?.emergencyStopped
                  ? `ON (v${overview.automation.control.version}) — 自動公開ブロック中`
                  : `OFF (v${overview?.automation?.control?.version ?? "?"})`}
              </li>
              <li>
                実効:{" "}
                {overview?.visualAutoPublishEnabled &&
                overview?.automation?.flags?.enabled &&
                overview?.automation?.flags?.autoPublishEnabled &&
                !overview?.automation?.control?.emergencyStopped
                  ? "自動公開可能"
                  : "自動公開不可（上記のいずれかが未達）"}
              </li>
            </ul>
          </div>
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
          <div className="rounded-lg border border-sky-500/30 bg-sky-500/5 px-3 py-3 space-y-2">
            <div className="text-sm font-medium text-sky-100">
              Limited Batch Canary（専用経路・Production batch とは別）
            </div>
            <ul className="text-xs text-gray-400 list-disc pl-4 space-y-0.5">
              <li>
                Emergency:{" "}
                {overview?.automation?.control?.emergencyStopped
                  ? `ON (v${overview.automation.control.version})`
                  : `OFF (v${overview?.automation?.control?.version ?? "?"})`}
              </li>
              <li>
                eligible candidates:{" "}
                {overview?.coverage?.eligiblePendingVideos ?? "—"}
              </li>
              <li>
                max 3 · concurrency 1（逐次）·{" "}
                <span className="text-amber-200">auto publish 強制 OFF</span> ·
                abort on 429
              </li>
              <li>force=false · allowLongform=true · stock analyzePending は使いません</li>
            </ul>
            <label className="block text-xs text-gray-300">
              videoIds（最大3・カンマまたは改行区切り）
              <textarea
                className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2 text-sm"
                rows={2}
                value={limitedBatchVideoIds}
                onChange={(e) => setLimitedBatchVideoIds(e.target.value)}
                placeholder="xxxxxxxxxxx,yyyyyyyyyyy,zzzzzzzzzzz"
              />
            </label>
            <button
              type="button"
              disabled={
                !secret ||
                busy ||
                (overview?.coverage?.eligiblePendingVideos ?? 0) < 1 ||
                overview?.automation?.control?.emergencyStopped === true ||
                limitedBatchVideoIds
                  .split(/[\s,]+/)
                  .map((s) => s.trim())
                  .filter(Boolean).length < 1
              }
              className="rounded-lg border border-sky-400/50 px-3 py-2 text-sm text-sky-100 disabled:opacity-40"
              onClick={() => {
                const videoIds = limitedBatchVideoIds
                  .split(/[\s,]+/)
                  .map((s) => s.trim())
                  .filter(Boolean)
                  .slice(0, 3);
                void postAction({
                  action: "runLimitedBatchCanary",
                  videoIds,
                });
              }}
            >
              Limited Batch Canary を実行
            </button>
            {(overview?.coverage?.eligiblePendingVideos ?? 0) < 1 ? (
              <p className="text-xs text-amber-200/90">
                eligible=0 のため実行ボタンは disabled（入力条件は緩和しません）。
              </p>
            ) : null}
          </div>

          <p className="text-xs text-gray-500 pt-1">Production batch（通常運用）</p>
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
              未カバーを3件だけ（Production）
            </button>
            <button
              type="button"
              disabled={!secret || busy}
              className="rounded-lg border border-emerald-400/40 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "recoverPostProcessFailures",
                  limit: 3,
                })
              }
            >
              postProcess失敗を復旧（最大3・AIなし）
            </button>
            <button
              type="button"
              disabled={!secret || busy}
              className="rounded-lg border border-white/20 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "getCoverageSnapshot",
                  eligibleLimit: 3,
                })
              }
            >
              Coverage再取得
            </button>
            <button
              type="button"
              disabled={!secret || !selectedVideoId || busy}
              className="rounded-lg border border-emerald-400/40 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "retryVisualPostProcess",
                  videoId: selectedVideoId,
                })
              }
            >
              選択動画のpostProcessのみ再実行
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
            <button
              type="button"
              disabled={!secret || busy}
              className="rounded-lg border border-sky-400/40 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "approvePendingVisualRecommendations",
                  limit: 20,
                })
              }
            >
              未公開の映像推奨を一括採用
            </button>
            <button
              type="button"
              disabled={!secret || busy}
              className="rounded-lg border border-emerald-400/40 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "publishPendingVisualRecommendations",
                  limit: 20,
                })
              }
            >
              未公開の映像推奨を一括公開
            </button>
          </div>
          <p className="text-xs text-gray-500">
            「全キャラ解析」は Production batch です（Limited Batch Canary とは別経路）。育成ガイド寄りの未解析動画から、まだ推奨のないキャラを1人1本ずつ解析します（目安50〜60本・数時間・Gemini費用あり）。日次上限は自動で300まで引き上げます。
            通常運用では解析成功後に自動公開します（visual env + automation/autoPublish flag + Emergency OFF）。
            {overview?.visualAutoPublishEnabled
              ? " BUILD_GUIDE_VISUAL_AUTO_PUBLISH=ON。構造化バリデーション失敗時は承認済みドラフトのまま公開だけスキップ。"
              : " いま visual env が OFF のため自動公開しません。「一括採用／一括公開」で手動対応できます。"}
            {overview?.automation?.control?.emergencyStopped
              ? " Global AI Emergency=ON のため自動公開はブロック中です。"
              : ""}
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
          <button
            type="button"
            disabled={!secret || busy}
            className="rounded-lg border border-sky-400/40 px-3 py-2 text-sm disabled:opacity-40"
            onClick={() =>
              void postAction({
                action: "approvePendingVisualRecommendations",
                limit: 20,
              })
            }
          >
            未公開の映像推奨を一括採用
          </button>
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
          emergencyStopped={
            overview?.automation?.control.emergencyStopped === true
          }
        />
      ) : null}

      {module === "recommendations" ? (
        <section className="space-y-3 rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
          <h2 className="font-bold">推奨詳細 / 承認・公開</h2>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={!secret || busy}
              className="rounded-lg border border-sky-400/40 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "approvePendingVisualRecommendations",
                  limit: 20,
                })
              }
            >
              未公開の映像推奨を一括採用
            </button>
            <button
              type="button"
              disabled={!secret || busy}
              className="rounded-lg border border-emerald-400/40 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "publishPendingVisualRecommendations",
                  limit: 20,
                })
              }
            >
              未公開の映像推奨を一括公開
            </button>
            <button
              type="button"
              disabled={!secret || busy}
              className="rounded-lg border border-violet-400/40 px-3 py-2 text-sm disabled:opacity-40"
              onClick={() =>
                void postAction({
                  action: "repromoteVisualGearMentions",
                  limit: 20,
                })
              }
            >
              武器・聖遺物言及を再昇格
            </button>
          </div>
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
                    onClick={() => {
                      const emergencyOn =
                        overview?.automation?.control.emergencyStopped === true;
                      let emergencyPublishOverrideReason: string | undefined;
                      if (emergencyOn) {
                        const reason = window.prompt(
                          "Global AI Emergency 中です。手動公開の break-glass 理由（8文字以上）を入力してください。",
                        );
                        if (!reason || reason.trim().length < 8) {
                          window.alert(
                            "公開を中止しました。緊急停止中の公開には理由が必要です。",
                          );
                          return;
                        }
                        emergencyPublishOverrideReason = reason.trim();
                      }
                      void postAction({
                        action: "publishRecommendation",
                        recommendationId: rec.id,
                        expectedUpdatedAt: rec.updatedAt,
                        ...(emergencyPublishOverrideReason
                          ? {
                              emergencyPublishOverrideReason,
                              emergencyPublishOverrideActor: "admin-ui",
                            }
                          : {}),
                      });
                    }}
                  >
                    {overview?.automation?.control.emergencyStopped
                      ? "公開（break-glass）"
                      : "公開"}
                  </button>
                  <button
                    type="button"
                    className="rounded border border-sky-400/40 px-2 py-1 text-xs"
                    disabled={busy}
                    onClick={() =>
                      void postAction({
                        action: "suggestPendingGearResolutions",
                        recommendationId: rec.id,
                      })
                    }
                  >
                    装備名の解決提案
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

      {module === "automation" ? (
        <section className="space-y-4 rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 className="font-bold">Global AI Emergency / YouTube 自動化</h2>
              <p className="text-sm text-gray-400">
                「緊急停止」は全AI（YouTube・Gemini・DeepSeek
                daily-plan/team/guide）と自動公開を止めます。字幕本文・AI
                prompt・provider response はこの画面へ返しません。
              </p>
            </div>
            <div className="flex gap-2">
              <button
                type="button"
                disabled={!secret || busy}
                className="rounded border border-red-400/60 px-3 py-2 text-sm text-red-200 disabled:opacity-40"
                onClick={() =>
                  void postAction({
                    action: "setYoutubeAutomationEmergencyStop",
                    emergencyStopped: true,
                    reason: "admin emergency stop",
                  })
                }
              >
                緊急停止
              </button>
              <button
                type="button"
                disabled={!secret || busy}
                className="rounded border border-white/20 px-3 py-2 text-sm disabled:opacity-40"
                onClick={() =>
                  void postAction({
                    action: "setYoutubeAutomationEmergencyStop",
                    emergencyStopped: false,
                    reason: "admin resumed",
                  })
                }
              >
                停止解除
              </button>
            </div>
          </div>

          <div className="grid gap-3 text-sm sm:grid-cols-2">
            <div className="rounded-lg bg-[#151d2a] p-3">
              <div className="font-medium">Global AI Emergency（安全スイッチ）</div>
              <div className="mt-1 text-gray-400">
                緊急停止:{" "}
                {overview?.automation?.control.emergencyStopped ? "ON" : "OFF"} ·
                version {overview?.automation?.control.version ?? 0}
              </div>
              <p className="mt-2 text-xs text-amber-200/80">
                ON中は新規AI呼び出しと自動公開を拒否します。手動公開は通常拒否され、理由付き
                break-glass override
                のみ許可（緊急停止自体は解除しません）。Daily-plan /
                Team は別env kill switchもありますが、Emergencyが優先されます。
              </p>
              <p className="mt-2 text-xs text-emerald-200/80">
                自動公開は通常運用です（visual=
                {overview?.visualAutoPublishEnabled ? "ON" : "OFF"} ·
                autoPublish=
                {overview?.automation?.flags?.autoPublishEnabled ? "ON" : "OFF"}
                ）。Canary 経路のみ skipAutoPublish で除外。実効:{" "}
                {overview?.visualAutoPublishEnabled &&
                overview?.automation?.flags?.enabled &&
                overview?.automation?.flags?.autoPublishEnabled &&
                !overview?.automation?.control?.emergencyStopped
                  ? "自動公開可能"
                  : "ブロック中"}
                。
              </p>
              <pre className="mt-2 whitespace-pre-wrap text-xs text-gray-500">
                {JSON.stringify(overview?.automation?.flags ?? {}, null, 2)}
              </pre>
            </div>
            <div className="rounded-lg bg-[#151d2a] p-3">
              <div className="font-medium">稼働状況</div>
              <div className="mt-1 text-gray-400">
                runs {overview?.automation?.runs.length ?? 0} · items{" "}
                {overview?.automation?.items.length ?? 0} · active leases{" "}
                {overview?.automation?.leases.length ?? 0}
              </div>
              <ul className="mt-2 space-y-1 text-xs text-gray-500">
                {(overview?.automation?.circuits ?? []).map((circuit) => (
                  <li key={circuit.providerId}>
                    {circuit.providerId}: {circuit.state} · failures{" "}
                    {circuit.failureCount}
                    {circuit.lastErrorCode ? ` · ${circuit.lastErrorCode}` : ""}
                  </li>
                ))}
              </ul>
            </div>
          </div>

          <div>
            <h3 className="text-sm font-bold">直近 item</h3>
            <ul className="mt-2 max-h-72 space-y-1 overflow-auto text-xs text-gray-400">
              {(overview?.automation?.items ?? []).map((item) => (
                <li key={item.id} className="rounded bg-[#151d2a] px-3 py-2">
                  {item.videoId} · {item.status} · attempts {item.attempts}/
                  {item.maxAttempts}
                  {item.blockCode ? ` · ${item.blockCode}` : ""}
                  {item.safeErrorCode ? ` · ${item.safeErrorCode}` : ""}
                </li>
              ))}
            </ul>
          </div>
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
