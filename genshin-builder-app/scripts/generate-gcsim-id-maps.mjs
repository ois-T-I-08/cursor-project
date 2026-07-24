import { createWriteStream, existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, basename } from "node:path";
import { pipeline } from "node:stream/promises";
import { execFileSync } from "node:child_process";
import { Readable } from "node:stream";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const appRoot = join(__dirname, "..");
const outTs = join(appRoot, "src/lib/team-recommendations/gcsim-id-maps.generated.ts");
const work = join(tmpdir(), "gcsim-v2.43.4-maps");
const tarPath = join(work, "src.tar.gz");

function walk(dir, acc = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, acc);
    else acc.push(p);
  }
  return acc;
}

function firstMatch(text, re) {
  const m = text.match(re);
  return m?.[1] ?? null;
}

mkdirSync(work, { recursive: true });
if (!existsSync(tarPath)) {
  console.log("Downloading gcsim v2.43.4 source...");
  const res = await fetch("https://github.com/genshinsim/gcsim/archive/refs/tags/v2.43.4.tar.gz");
  if (!res.ok) throw new Error(`download failed: ${res.status}`);
  await pipeline(Readable.fromWeb(res.body), createWriteStream(tarPath));
}

console.log("Extracting...");
execFileSync("tar", ["-xzf", tarPath, "-C", work], { stdio: "inherit" });
const root = readdirSync(work)
  .map((name) => join(work, name))
  .find((p) => statSync(p).isDirectory() && basename(p).startsWith("gcsim-"));
if (!root) throw new Error("extracted root not found");

const characters = {};
const weapons = {};
const artifacts = {};
for (const file of walk(root)) {
  const norm = file.replaceAll("\\", "/");
  if (norm.includes("/internal/characters/") && norm.endsWith("data_gen.textproto")) {
    const text = readFileSync(file, "utf8");
    const id = firstMatch(text, /^id:\s*(\d+)/m);
    const key = firstMatch(text, /^key:\s*"([^"]+)"/m);
    if (id && key) characters[id] = key;
  }
  if (norm.includes("/internal/weapons/") && norm.endsWith("data_gen.textproto")) {
    const text = readFileSync(file, "utf8");
    const id = firstMatch(text, /^id:\s*(\d+)/m);
    const key = firstMatch(text, /^key:\s*"([^"]+)"/m);
    if (id && key) weapons[id] = key;
  }
  if (norm.includes("/internal/artifacts/") && norm.endsWith("config.yml")) {
    const text = readFileSync(file, "utf8");
    const id = firstMatch(text, /\bset_id:\s*(\d+)/) ?? firstMatch(text, /\bid:\s*(\d+)/);
    const key = firstMatch(text, /\bkey:\s*["']?([A-Za-z0-9_]+)["']?/) ?? basename(dirname(file));
    if (id && key) artifacts[id] = key;
  }
}

console.log({
  characters: Object.keys(characters).length,
  weapons: Object.keys(weapons).length,
  artifacts: Object.keys(artifacts).length,
  sample133: characters["10000133"],
  sample89: characters["10000089"],
  kuki: characters["10000065"],
});

writeFileSync(
  outTs,
  `/* Generated from gcsim v2.43.4 data_gen / config.yml. Do not edit by hand.\n` +
    ` * Regenerate: node scripts/generate-gcsim-id-maps.mjs\n` +
    ` */\n` +
    `export const GCSIM_CHARACTER_KEYS: Readonly<Record<string, string>> = ${JSON.stringify(characters, null, 2)} as const;\n` +
    `export const GCSIM_WEAPON_KEYS: Readonly<Record<string, string>> = ${JSON.stringify(weapons, null, 2)} as const;\n` +
    `export const GCSIM_ARTIFACT_KEYS: Readonly<Record<string, string>> = ${JSON.stringify(artifacts, null, 2)} as const;\n`,
);
console.log("Wrote", outTs);
