import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { PrismaClient } from "@prisma/client";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl || process.env.CI_DISPOSABLE_DATABASE !== "true") {
  throw new Error("migrationAtomicityRequiresDisposableDatabase");
}
const parsedUrl = new URL(databaseUrl);
if (
  !["localhost", "127.0.0.1"].includes(parsedUrl.hostname) ||
  !parsedUrl.pathname.endsWith("/genshin_test")
) {
  throw new Error("migrationAtomicityRefusesNonLocalDatabase");
}

const upgradeSchema = "youtube_hardening_upgrade";
const interruptedSchema = "youtube_hardening_interrupted";
const root = resolve(import.meta.dirname, "..");
const migrations = resolve(root, "prisma", "migrations");
const baseline = resolve(
  migrations,
  "20260728220000_postgresql_baseline",
  "migration.sql",
);
const cacheDrop = resolve(
  migrations,
  "20260730120000_drop_team_simulation_cache",
  "migration.sql",
);
const automation = resolve(
  migrations,
  "20260731120000_add_youtube_automation_pipeline",
  "migration.sql",
);
const hardening = resolve(
  migrations,
  "20260731153000_harden_youtube_automation_pipeline",
  "migration.sql",
);
const circuitFencing = resolve(
  migrations,
  "20260731180000_fence_provider_circuit_probe",
  "migration.sql",
);
const temp = mkdtempSync(join(tmpdir(), "youtube-hardening-"));
const fixtureSql = join(temp, "fixture.sql");
const interruptedSql = join(temp, "interrupted.sql");
const circuitInterruptedSql = join(temp, "circuit-interrupted.sql");
const npx = process.platform === "win32" ? "npx.cmd" : "npx";

const admin = new PrismaClient();
try {
  await admin.$executeRawUnsafe(`CREATE SCHEMA "${upgradeSchema}"`);
  await admin.$executeRawUnsafe(`CREATE SCHEMA "${interruptedSchema}"`);

  const fixture = `
    INSERT INTO "GuideChannel"
      ("id", "channelId", "title", "updatedAt")
    VALUES
      ('migration-channel-id', 'migration-channel', 'fixture', CURRENT_TIMESTAMP);
    INSERT INTO "GuideVideo"
      ("id", "videoId", "channelId", "title", "sourceUrl", "updatedAt")
    VALUES
      (
        'migration-video-id',
        'migration-video',
        'migration-channel',
        'fixture',
        'https://www.youtube.com/watch?v=migration-video',
        CURRENT_TIMESTAMP
      );
    INSERT INTO "GuidePipelineRun"
      (
        "id",
        "pipelineRunId",
        "idempotencyKey",
        "trigger",
        "policyVersion",
        "policyHash",
        "updatedAt"
      )
    VALUES
      (
        'migration-run-id',
        'migration-run',
        'migration-run-key',
        'test',
        'fixture',
        'fixture',
        CURRENT_TIMESTAMP
      );
    INSERT INTO "GuidePipelineItem"
      ("id", "runId", "videoId", "discoveryKey", "updatedAt")
    VALUES
      (
        'migration-item-id',
        'migration-run-id',
        'migration-video',
        'migration-discovery',
        CURRENT_TIMESTAMP
      );
    INSERT INTO "GuideProviderCircuit"
      (
        "providerId",
        "state",
        "failureCount",
        "halfOpenProbeAt",
        "version",
        "updatedAt"
      )
    VALUES
      (
        'migration-provider',
        'half_open',
        3,
        CURRENT_TIMESTAMP,
        7,
        CURRENT_TIMESTAMP
      );
  `;
  writeFileSync(fixtureSql, fixture, "utf8");

  for (const schema of [upgradeSchema, interruptedSchema]) {
    const url = schemaUrl(schema);
    executeSql(url, baseline);
    executeSql(url, cacheDrop);
    executeSql(url, automation);
    executeSql(url, fixtureSql);
  }

  executeSql(schemaUrl(upgradeSchema), hardening);
  executeSql(schemaUrl(upgradeSchema), circuitFencing);
  const upgraded = clientFor(upgradeSchema);
  try {
    const item = await upgraded.guidePipelineItem.findUniqueOrThrow({
      where: { id: "migration-item-id" },
      select: {
        runId: true,
        activeRunId: true,
        lastRunId: true,
        stateVersion: true,
      },
    });
    if (
      item.activeRunId !== item.runId ||
      item.lastRunId !== item.runId ||
      item.stateVersion !== 0
    ) {
      throw new Error("hardeningBackfillFailed");
    }
    const circuit = await upgraded.guideProviderCircuit.findUniqueOrThrow({
      where: { providerId: "migration-provider" },
    });
    if (
      circuit.state !== "open" ||
      circuit.openUntil === null ||
      circuit.probeOwner !== "" ||
      circuit.probeToken !== 0 ||
      circuit.probeAcquiredAt !== null ||
      circuit.probeExpiresAt !== null ||
      circuit.stateVersion !== 8
    ) {
      throw new Error("circuitFencingBackfillFailed");
    }
  } finally {
    await upgraded.$disconnect();
  }

  const hardeningSql = readFileSync(hardening, "utf8");
  if (!/\bBEGIN;\s/i.test(hardeningSql) || !/\bCOMMIT;\s*$/i.test(hardeningSql)) {
    throw new Error("hardeningMigrationMustBeTransactional");
  }
  writeFileSync(
    interruptedSql,
    hardeningSql.replace(
      /\bCOMMIT;\s*$/i,
      "SELECT 1 / 0;\n\nCOMMIT;\n",
    ),
    "utf8",
  );
  let interrupted = false;
  try {
    executeSql(schemaUrl(interruptedSchema), interruptedSql);
  } catch {
    interrupted = true;
  }
  if (!interrupted) throw new Error("interruptedMigrationDidNotFail");

  const interruptedClient = clientFor(interruptedSchema);
  try {
    const columns = await interruptedClient.$queryRawUnsafe(
      `SELECT "column_name"
       FROM "information_schema"."columns"
       WHERE "table_schema" = '${interruptedSchema}'
         AND "table_name" = 'GuidePipelineItem'
         AND "column_name" IN (
           'activeRunId',
           'lastRunId',
           'characterId',
           'transcriptId',
           'stateVersion',
           'leaseOwner',
           'leaseVersion',
           'canonicalAnalysisPayload',
           'validationHash',
           'snapshotPayload',
           'policyHash'
         )`,
    );
    const indexes = await interruptedClient.$queryRawUnsafe(
      `SELECT "indexname"
       FROM "pg_indexes"
       WHERE "schemaname" = '${interruptedSchema}'
         AND "indexname" IN (
           'GuidePipelineItem_characterId_status_idx',
           'GuidePipelineItem_activeRunId_status_idx',
           'GuidePipelineItem_transcriptId_idx'
         )`,
    );
    const constraints = await interruptedClient.$queryRawUnsafe(
      `SELECT "constraint_name"
       FROM "information_schema"."table_constraints"
       WHERE "table_schema" = '${interruptedSchema}'
         AND "constraint_name" = 'GuidePipelineItem_transcriptId_fkey'`,
    );
    const rows = await interruptedClient.$queryRawUnsafe(
      `SELECT COUNT(*)::int AS "count"
       FROM "GuidePipelineItem"
       WHERE "id" = 'migration-item-id'`,
    );
    if (
      columns.length !== 0 ||
      indexes.length !== 0 ||
      constraints.length !== 0 ||
      rows[0]?.count !== 1
    ) {
      throw new Error("interruptedMigrationLeftPartialState");
    }
  } finally {
    await interruptedClient.$disconnect();
  }

  // A clean retry after rollback must apply normally.
  executeSql(schemaUrl(interruptedSchema), hardening);
  const retried = clientFor(interruptedSchema);
  try {
    const item = await retried.guidePipelineItem.findUniqueOrThrow({
      where: { id: "migration-item-id" },
      select: { activeRunId: true, lastRunId: true },
    });
    if (
      item.activeRunId !== "migration-run-id" ||
      item.lastRunId !== "migration-run-id"
    ) {
      throw new Error("hardeningRetryFailed");
    }
  } finally {
    await retried.$disconnect();
  }

  const circuitFencingSql = readFileSync(circuitFencing, "utf8");
  if (
    !/\bBEGIN;\s/i.test(circuitFencingSql) ||
    !/\bCOMMIT;\s*$/i.test(circuitFencingSql)
  ) {
    throw new Error("circuitFencingMigrationMustBeTransactional");
  }
  writeFileSync(
    circuitInterruptedSql,
    circuitFencingSql.replace(
      /\bCOMMIT;\s*$/i,
      "SELECT 1 / 0;\n\nCOMMIT;\n",
    ),
    "utf8",
  );
  let circuitInterrupted = false;
  try {
    executeSql(schemaUrl(interruptedSchema), circuitInterruptedSql);
  } catch {
    circuitInterrupted = true;
  }
  if (!circuitInterrupted) {
    throw new Error("interruptedCircuitFencingMigrationDidNotFail");
  }

  const interruptedCircuitClient = clientFor(interruptedSchema);
  try {
    const columns = await interruptedCircuitClient.$queryRawUnsafe(
      `SELECT "column_name"
       FROM "information_schema"."columns"
       WHERE "table_schema" = '${interruptedSchema}'
         AND "table_name" = 'GuideProviderCircuit'
         AND "column_name" IN (
           'probeOwner',
           'probeToken',
           'probeAcquiredAt',
           'probeExpiresAt',
           'stateVersion'
         )`,
    );
    const oldColumns = await interruptedCircuitClient.$queryRawUnsafe(
      `SELECT "column_name"
       FROM "information_schema"."columns"
       WHERE "table_schema" = '${interruptedSchema}'
         AND "table_name" = 'GuideProviderCircuit'
         AND "column_name" IN ('halfOpenProbeAt', 'version')`,
    );
    const rows = await interruptedCircuitClient.$queryRawUnsafe(
      `SELECT "state", "version", "halfOpenProbeAt"
       FROM "GuideProviderCircuit"
       WHERE "providerId" = 'migration-provider'`,
    );
    if (
      columns.length !== 0 ||
      oldColumns.length !== 2 ||
      rows.length !== 1 ||
      rows[0]?.state !== "half_open" ||
      rows[0]?.version !== 7 ||
      rows[0]?.halfOpenProbeAt === null
    ) {
      throw new Error("interruptedCircuitFencingLeftPartialState");
    }
  } finally {
    await interruptedCircuitClient.$disconnect();
  }

  executeSql(schemaUrl(interruptedSchema), circuitFencing);
  const retriedCircuitClient = clientFor(interruptedSchema);
  try {
    const circuit =
      await retriedCircuitClient.guideProviderCircuit.findUniqueOrThrow({
        where: { providerId: "migration-provider" },
      });
    if (
      circuit.state !== "open" ||
      circuit.openUntil === null ||
      circuit.stateVersion !== 8 ||
      circuit.probeAcquiredAt !== null ||
      circuit.probeExpiresAt !== null
    ) {
      throw new Error("circuitFencingRetryFailed");
    }
  } finally {
    await retriedCircuitClient.$disconnect();
  }
} finally {
  await admin.$disconnect();
}

function schemaUrl(schema) {
  const value = new URL(databaseUrl);
  value.searchParams.set("schema", schema);
  return value.toString();
}

function clientFor(schema) {
  return new PrismaClient({
    datasources: { db: { url: schemaUrl(schema) } },
  });
}

function executeSql(url, file) {
  execFileSync(
    npx,
    ["prisma", "db", "execute", "--url", url, "--file", file],
    {
      cwd: root,
      env: process.env,
      stdio: "pipe",
    },
  );
}
