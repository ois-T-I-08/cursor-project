#!/usr/bin/env node
/**
 * Gate-only dry-run smoke for staging admin API (Tier A).
 * Flags stay OFF -> pipeline returns skipped summary before providers/DB writes.
 *
 * Reads BUILD_GUIDE_ADMIN_SECRET from env - never prints it.
 *
 * Usage (PowerShell):
 *   $env:BUILD_GUIDE_ADMIN_SECRET = (Get-Clipboard).Trim()  # or paste staging value
 *   node genshin-builder-app/scripts/gate-only-smoke.mjs
 *   Remove-Item Env:BUILD_GUIDE_ADMIN_SECRET
 *
 * Admin GET nests automation under `automation` (not top-level flags/control).
 */
import { writeFileSync, unlinkSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const BASE = process.env.STAGING_API_BASE_URL || "https://staging-sable.vercel.app";
// Clipboard / paste often adds CR/LF / BOM; strip edge + line breaks only.
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
console.log(`GET_starts_with_brace=${getText.trimStart().startsWith("{")}`);

if (!getText.trimStart().startsWith("{")) {
  fail("GET_not_json");
}

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
if (!automation || typeof automation !== "object") {
  fail("automation_block_missing");
}

const flags = automation.flags || {};
const control = automation.control || {};
const rows = {
  YOUTUBE_GUIDE_ENABLED: Boolean(flags.guideEnabled),
  // flags.enabled === (YOUTUBE_AUTOMATION_ENABLED && YOUTUBE_GUIDE_ENABLED)
  YOUTUBE_AUTOMATION_PIPELINE_ENABLED: Boolean(flags.enabled),
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
console.log(`runs=${(automation.runs || []).length}`);
console.log(`items=${(automation.items || []).length}`);
console.log(`circuits=${(automation.circuits || []).length}`);
console.log(`leases=${(automation.leases || []).length}`);

const anyFlagOn = Object.values(rows).some(Boolean);
if (anyFlagOn) fail("flags_not_all_off");

// Keep within route regex: ^[A-Za-z0-9][A-Za-z0-9._:-]{5,100}$
const safeRunId = `admin:staging-gate-smoke:${Date.now()}`;

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

const postFile = join(tmpdir(), `youtube-guide-gate-smoke-${Date.now()}.json`);
const sumFile = join(tmpdir(), `youtube-guide-gate-smoke-${Date.now()}.md`);
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

const countsZero =
  s.discovered === 0 &&
  s.published === 0 &&
  s.ready === 0 &&
  s.reviewRequired === 0 &&
  s.blocked === 0 &&
  s.stopped === 0 &&
  s.retryable === 0;

if (
  postJson.ok !== true ||
  s.skipped !== true ||
  s.dryRun !== true ||
  s.pipelineRunId !== safeRunId ||
  !countsZero
) {
  fail("summary_mismatch");
}

// Side-effect check: GET again (automation counts must not grow on skip path)
const get2 = await fetch(`${BASE}/api/admin/build-guides`, { headers });
const get2Json = await get2.json();
const a2 = get2Json.automation || {};
console.log(
  `runs_delta=${(a2.runs || []).length - (automation.runs || []).length}`,
);
console.log(
  `items_delta=${(a2.items || []).length - (automation.items || []).length}`,
);
console.log(
  `circuits_delta=${(a2.circuits || []).length - (automation.circuits || []).length}`,
);
console.log(
  `leases_delta=${(a2.leases || []).length - (automation.leases || []).length}`,
);

if (
  (a2.runs || []).length !== (automation.runs || []).length ||
  (a2.items || []).length !== (automation.items || []).length ||
  (a2.circuits || []).length !== (automation.circuits || []).length ||
  (a2.leases || []).length !== (automation.leases || []).length
) {
  fail("side_effect_detected");
}

console.log("GATE_SMOKE=PASS");
