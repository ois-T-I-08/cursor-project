#!/usr/bin/env node
/**
 * Tier B provider dry-run smoke for staging admin API.
 * Expects guide+automation+discovery+gemini ON; auto-publish/maintenance OFF.
 * dryRun:true -> may write pipeline rows; must not publish.
 *
 * Reads BUILD_GUIDE_ADMIN_SECRET from env - never prints it.
 *
 * Usage (PowerShell):
 *   $env:BUILD_GUIDE_ADMIN_SECRET = (Get-Clipboard).Trim()
 *   node genshin-builder-app/scripts/provider-dry-run-smoke.mjs
 *   Remove-Item Env:BUILD_GUIDE_ADMIN_SECRET
 */
import { writeFileSync, unlinkSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const BASE = process.env.STAGING_API_BASE_URL || "https://staging-sable.vercel.app";
const secret = (process.env.BUILD_GUIDE_ADMIN_SECRET || "")
  .replace(/^\uFEFF/, "")
  .replace(/[\r\n\t]+/g, "")
  .trim();

function fail(msg) {
  console.error(`FAIL=${msg}`);
  process.exit(2);
}

if (!secret) fail("BUILD_GUIDE_ADMIN_SECRET_missing");
if (/\s/.test(secret)) fail("BUILD_GUIDE_ADMIN_SECRET_has_whitespace");
if (
  secret === "..." ||
  secret === "BUILD_GUIDE_ADMIN" ||
  secret === "BUILD_GUIDE_ADMIN_SECRET"
) {
  fail("BUILD_GUIDE_ADMIN_SECRET_looks_like_placeholder");
}

const headers = {
  Authorization: `Bearer ${secret}`,
  Accept: "application/json",
};

const getRes = await fetch(`${BASE}/api/admin/build-guides`, {
  method: "GET",
  headers,
});
const getText = await getRes.text();
console.log(`GET_status=${getRes.status}`);
console.log(`GET_contentType=${(getRes.headers.get("content-type") || "").split(";")[0]}`);
console.log(`GET_bytes=${Buffer.byteLength(getText)}`);

if (!getText.trimStart().startsWith("{")) fail("GET_not_json");
let getJson;
try {
  getJson = JSON.parse(getText);
} catch {
  fail("GET_json_parse");
}
console.log(`GET_error=${getJson.error || ""}`);

if (getRes.status === 401) fail("GET_unauthorized_missing_or_malformed_bearer");
if (getRes.status === 403) fail("GET_forbidden_secret_mismatch");
if (getRes.status === 503) fail("GET_unavailable_server_secret_unset");
if (!getRes.ok) fail(`GET_http_${getRes.status}`);

const automation = getJson.automation;
if (!automation || typeof automation !== "object") fail("automation_block_missing");

const flags = automation.flags || {};
const control = automation.control || {};
const channels = Array.isArray(getJson.channels) ? getJson.channels : [];
const approvedChannels = channels.filter(
  (c) => c && c.permissionStatus === "approved_for_processing" && c.enabled !== false,
);

const rows = {
  guideEnabled: Boolean(flags.guideEnabled),
  pipelineEnabled: Boolean(flags.enabled),
  discoveryEnabled: Boolean(flags.discoveryEnabled),
  transcriptEnabled: Boolean(flags.transcriptEnabled),
  analysisEnabled: Boolean(flags.analysisEnabled),
  geminiAnalysisEnabled: Boolean(flags.geminiAnalysisEnabled),
  deepseekAnalysisEnabled: Boolean(flags.deepseekAnalysisEnabled),
  autoPublishEnabled: Boolean(flags.autoPublishEnabled),
  maintenanceEnabled: Boolean(flags.maintenanceEnabled),
};
for (const [k, v] of Object.entries(rows)) console.log(`${k}=${v}`);
console.log(`emergencyStopped=${control.emergencyStopped === true}`);
console.log(`control_reason=${control.reason || ""}`);
console.log(`control_version=${control.version ?? ""}`);
console.log(`channels_total=${channels.length}`);
console.log(`channels_approved=${approvedChannels.length}`);
console.log(`runs_before=${(automation.runs || []).length}`);
console.log(`items_before=${(automation.items || []).length}`);

if (!rows.guideEnabled) fail("guide_not_enabled");
if (!rows.pipelineEnabled) fail("pipeline_not_enabled");
if (!rows.discoveryEnabled) fail("discovery_not_enabled");
if (!rows.transcriptEnabled) fail("transcript_not_enabled");
if (!rows.analysisEnabled) fail("analysis_not_enabled");
if (!rows.geminiAnalysisEnabled) fail("gemini_not_enabled");
if (rows.deepseekAnalysisEnabled) fail("deepseek_must_stay_off");
if (rows.autoPublishEnabled) fail("auto_publish_must_stay_off");
if (rows.maintenanceEnabled) fail("maintenance_must_stay_off");
if (control.emergencyStopped === true) fail("emergency_stopped");
if (control.reason === "CONTROL_ROW_MISSING") fail("control_row_missing");

const safeRunId = `admin:staging-tierb-smoke:${Date.now()}`;
const postRes = await fetch(`${BASE}/api/admin/youtube/pipeline/run`, {
  method: "POST",
  headers: {
    ...headers,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    pipelineRunId: safeRunId,
    trigger: "admin",
    dryRun: true,
  }),
});
const postText = await postRes.text();
console.log(`POST_status=${postRes.status}`);
console.log(`POST_contentType=${(postRes.headers.get("content-type") || "").split(";")[0]}`);
console.log(`POST_bytes=${Buffer.byteLength(postText)}`);

if (!postRes.ok || !postText.trimStart().startsWith("{")) {
  fail("POST_not_json_ok");
}

const postFile = join(tmpdir(), `youtube-guide-tierb-smoke-${Date.now()}.json`);
const sumFile = join(tmpdir(), `youtube-guide-tierb-smoke-${Date.now()}.md`);
const formatter = join(__dirname, "format-youtube-guide-job-summary.mjs");
writeFileSync(postFile, postText, "utf8");
const fmt = spawnSync(process.execPath, [formatter, postFile, sumFile], {
  encoding: "utf8",
});
console.log(`formatter_exit=${fmt.status ?? 1}`);
try {
  unlinkSync(postFile);
} catch {
  /* ignore */
}
try {
  unlinkSync(sumFile);
} catch {
  /* ignore */
}
if (fmt.status !== 0) fail("formatter_failed");

const postJson = JSON.parse(postText);
const s = postJson.summary || {};
console.log(`ok=${postJson.ok === true}`);
console.log(`pipelineRunId_match=${s.pipelineRunId === safeRunId}`);
console.log(`skipped=${s.skipped}`);
console.log(`dryRun=${s.dryRun}`);
console.log(`discovered=${s.discovered}`);
console.log(`published=${s.published}`);
console.log(`ready=${s.ready}`);
console.log(`reviewRequired=${s.reviewRequired}`);
console.log(`blocked=${s.blocked}`);
console.log(`stopped=${s.stopped}`);
console.log(`retryable=${s.retryable}`);

if (postJson.ok !== true) fail("response_not_ok");
if (s.pipelineRunId !== safeRunId) fail("pipeline_run_id_mismatch");
if (s.dryRun !== true) fail("dry_run_false");
if (s.skipped === true) fail("unexpected_skipped");
if (s.published !== 0) fail("published_nonzero");
if (s.stopped > 0) fail("unexpected_stopped");

const get2 = await fetch(`${BASE}/api/admin/build-guides`, { headers });
const get2Json = await get2.json();
const a2 = get2Json.automation || {};
const items = a2.items || [];
const runs = a2.runs || [];
console.log(`runs_after=${runs.length}`);
console.log(`items_after=${items.length}`);
console.log(
  `runs_delta=${runs.length - (automation.runs || []).length}`,
);
console.log(
  `items_delta=${items.length - (automation.items || []).length}`,
);

const statuses = {};
const blockCodes = {};
for (const item of items.slice(0, 100)) {
  const st = String(item.status || "unknown");
  statuses[st] = (statuses[st] || 0) + 1;
  const code = item.blockCode || item.safeErrorCode;
  if (code) blockCodes[String(code)] = (blockCodes[String(code)] || 0) + 1;
}
console.log(`item_status_counts=${JSON.stringify(statuses)}`);
console.log(`item_block_or_error_codes=${JSON.stringify(blockCodes)}`);

const pubProbe = await fetch(`${BASE}/api/v2/build-recommendations/xingqiu`);
const pubText = await pubProbe.text();
console.log(`public_v2_status=${pubProbe.status}`);
console.log(
  `public_v2_notFound=${pubText.includes('"notFound"') || pubText.includes('"error":"notFound"')}`,
);

console.log("TIER_B_SMOKE=PASS");
console.log(`note_approved_channels=${approvedChannels.length}`);
if (approvedChannels.length === 0) {
  console.log("note=no_approved_channels_discovered_may_be_zero");
}
console.log("note=oauth_token_not_checked_here_transcript_may_block");
