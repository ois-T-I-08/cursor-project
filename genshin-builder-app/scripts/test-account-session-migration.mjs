import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { PrismaClient } from "@prisma/client";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl || process.env.CI_DISPOSABLE_DATABASE !== "true") {
  throw new Error("accountSessionMigrationRequiresDisposableDatabase");
}
const parsedUrl = new URL(databaseUrl);
if (
  !["localhost", "127.0.0.1"].includes(parsedUrl.hostname) ||
  !parsedUrl.pathname.endsWith("/genshin_test")
) {
  throw new Error("accountSessionMigrationRefusesNonLocalDatabase");
}

const upgradeSchema = "account_session_upgrade";
const interruptedSchema = "account_session_interrupted";
const root = resolve(import.meta.dirname, "..");
const migrationsRoot = resolve(root, "prisma", "migrations");
const migrationFiles = [
  "20260728220000_postgresql_baseline",
  "20260730120000_drop_team_simulation_cache",
  "20260731120000_add_youtube_automation_pipeline",
  "20260731153000_harden_youtube_automation_pipeline",
  "20260731180000_fence_provider_circuit_probe",
].map((name) => resolve(migrationsRoot, name, "migration.sql"));
const accountSessionMigration = resolve(
  migrationsRoot,
  "20260806120000_add_account_session_foundation",
  "migration.sql",
);
const temporaryDirectory = mkdtempSync(join(tmpdir(), "account-session-migration-"));
const fixtureSql = join(temporaryDirectory, "legacy-fixture.sql");
const interruptedSql = join(temporaryDirectory, "interrupted.sql");
const npx = process.platform === "win32" ? "npx.cmd" : "npx";

writeFileSync(
  fixtureSql,
  `
    INSERT INTO "Character"
      ("id", "name", "element", "weaponType", "rarity", "region", "iconUrl", "syncedAt")
    VALUES
      ('account-migration-character', 'fixture', 'anemo', 'sword', 5, 'test', 'https://example.com/icon.png', CURRENT_TIMESTAMP);
    INSERT INTO "UserProgress"
      ("id", "userId", "characterId", "updatedAt")
    VALUES
      ('account-migration-progress', 'legacy-gb-user', 'account-migration-character', CURRENT_TIMESTAMP);
  `,
  "utf8",
);

const admin = new PrismaClient();
try {
  for (const schema of [upgradeSchema, interruptedSchema]) {
    await admin.$executeRawUnsafe(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
    await admin.$executeRawUnsafe(`CREATE SCHEMA "${schema}"`);
    for (const migration of migrationFiles) executeSql(schemaUrl(schema), migration);
    executeSql(schemaUrl(schema), fixtureSql);
  }

  executeSql(schemaUrl(upgradeSchema), accountSessionMigration);
  await verifyUpgrade(upgradeSchema);

  const migrationSql = readFileSync(accountSessionMigration, "utf8");
  if (!/\bBEGIN;\s/i.test(migrationSql) || !/\bCOMMIT;\s*$/i.test(migrationSql)) {
    throw new Error("accountSessionMigrationMustBeTransactional");
  }
  writeFileSync(
    interruptedSql,
    migrationSql.replace(
      /\bCOMMIT;\s*$/i,
      "SELECT 1 / 0;\n\nCOMMIT;\n",
    ),
    "utf8",
  );

  let interruptionObserved = false;
  try {
    executeSql(schemaUrl(interruptedSchema), interruptedSql);
  } catch {
    interruptionObserved = true;
  }
  if (!interruptionObserved) throw new Error("accountSessionInterruptionDidNotFail");
  await verifyInterruptedRollback(interruptedSchema);

  executeSql(schemaUrl(interruptedSchema), accountSessionMigration);
  await verifyUpgrade(interruptedSchema);
} finally {
  for (const schema of [upgradeSchema, interruptedSchema]) {
    await admin.$executeRawUnsafe(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
  }
  await admin.$disconnect();
}

async function verifyUpgrade(schema) {
  const client = clientFor(schema);
  try {
    const progress = await client.$queryRawUnsafe(
      `SELECT "userId", "characterId"
       FROM "UserProgress"
       WHERE "id" = 'account-migration-progress'`,
    );
    if (
      progress.length !== 1 ||
      progress[0]?.userId !== "legacy-gb-user" ||
      progress[0]?.characterId !== "account-migration-character"
    ) {
      throw new Error("legacyUserProgressChangedDuringAccountMigration");
    }

    const tables = await client.$queryRawUnsafe(
      `SELECT "table_name"
       FROM "information_schema"."tables"
       WHERE "table_schema" = '${schema}'
         AND "table_name" IN ('Account', 'AuthIdentity', 'WebSession', 'AnonymousIdentity')`,
    );
    if (tables.length !== 4) throw new Error("accountSessionTablesMissing");

    const constraints = await client.$queryRawUnsafe(
      `SELECT "constraint_name"
       FROM "information_schema"."table_constraints"
       WHERE "table_schema" = '${schema}'
         AND "constraint_name" IN (
           'Account_status_check',
           'Account_version_positive_check',
           'AuthIdentity_accountId_fkey',
           'WebSession_accountId_fkey',
           'WebSession_replacedBySessionId_fkey',
           'WebSession_tokenHash_format_check',
           'AnonymousIdentity_claimedAccountId_fkey',
           'AnonymousIdentity_secretHash_format_check'
         )`,
    );
    if (constraints.length !== 8) {
      throw new Error("accountSessionConstraintsMissing");
    }

    const indexes = await client.$queryRawUnsafe(
      `SELECT "indexname"
       FROM "pg_indexes"
       WHERE "schemaname" = '${schema}'
         AND "indexname" IN (
           'Account_status_idx',
           'Account_deletionRequestedAt_idx',
           'AuthIdentity_provider_providerSubject_key',
           'AuthIdentity_accountId_idx',
           'WebSession_tokenHash_key',
           'WebSession_replacedBySessionId_key',
           'WebSession_accountId_revokedAt_idx',
           'WebSession_expiresAt_idx',
           'WebSession_lastSeenAt_idx',
           'AnonymousIdentity_secretHash_key',
           'AnonymousIdentity_expiresAt_idx',
           'AnonymousIdentity_revokedAt_idx',
           'AnonymousIdentity_claimedAccountId_idx'
         )`,
    );
    if (indexes.length !== 13) throw new Error("accountSessionIndexesMissing");
  } finally {
    await client.$disconnect();
  }
}

async function verifyInterruptedRollback(schema) {
  const client = clientFor(schema);
  try {
    const tables = await client.$queryRawUnsafe(
      `SELECT "table_name"
       FROM "information_schema"."tables"
       WHERE "table_schema" = '${schema}'
         AND "table_name" IN ('Account', 'AuthIdentity', 'WebSession', 'AnonymousIdentity')`,
    );
    const progress = await client.$queryRawUnsafe(
      `SELECT COUNT(*)::int AS "count"
       FROM "UserProgress"
       WHERE "id" = 'account-migration-progress'
         AND "userId" = 'legacy-gb-user'`,
    );
    if (tables.length !== 0 || progress[0]?.count !== 1) {
      throw new Error("accountSessionInterruptedMigrationLeftPartialState");
    }
  } finally {
    await client.$disconnect();
  }
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
  execFileSync(npx, ["prisma", "db", "execute", "--url", url, "--file", file], {
    cwd: root,
    env: process.env,
    stdio: "pipe",
  });
}
