/**
 * Actions-driven YShelper collector.
 * Fetches YShelper, validates, and writes Neon via Prisma in-process.
 * Does not call the Next.js HTTP collect route.
 *
 *   npm run yshelper:collect
 *
 * Kill switches must be explicit true. Defaults remain disabled.
 * Never logs URLs, tokens, cookies, or upstream bodies.
 */
import { PrismaClient } from "@prisma/client";

import {
  configuredYshelperAdapter,
  YshelperAdapterNotConfiguredError,
} from "../src/lib/yshelper/adapter";
import {
  BattleStatsCollectorAlreadyRunningError,
  BattleStatsCollectorService,
  readEnabledContentTypes,
  runBattleStatsCollectorExclusive,
} from "../src/lib/yshelper/collector";
import { YshelperHttpClient } from "../src/lib/yshelper/client";
import { hostKindFromDatabaseUrl } from "../src/lib/yshelper/dry-run-db";
import { PrismaBattleStatsStore } from "../src/lib/yshelper/store";

function assertNeonDatabaseUrl(): void {
  const kind = hostKindFromDatabaseUrl(process.env.DATABASE_URL);
  if (kind === "missing" || kind === "parse-error") {
    throw new Error("database_url_invalid");
  }
  if (kind === "localhost") {
    throw new Error("database_url_localhost_rejected");
  }
}

function createCliService(): BattleStatsCollectorService {
  const contentTypes = readEnabledContentTypes(process.env);
  if (contentTypes.length === 0) {
    throw new Error("collector_disabled");
  }
  return new BattleStatsCollectorService(
    new PrismaBattleStatsStore(),
    new YshelperHttpClient(),
    configuredYshelperAdapter(),
    { enabledContentTypes: () => contentTypes },
  );
}

async function main(): Promise<void> {
  const enabled = readEnabledContentTypes(process.env);
  console.info("yshelper_collect", {
    phase: "start",
    enabledCount: enabled.length,
    abyssEnabled: enabled.includes("abyss"),
    stygianEnabled: enabled.includes("stygian"),
    databaseKind: hostKindFromDatabaseUrl(process.env.DATABASE_URL),
  });

  if (enabled.length === 0) {
    console.info("yshelper_collect", {
      phase: "skipped",
      reason: "disabled",
      exitCode: 0,
    });
    return;
  }

  assertNeonDatabaseUrl();
  // Touch Prisma so generate/env issues fail before upstream fetch.
  const probe = new PrismaClient();
  try {
    await probe.$queryRaw`SELECT 1`;
  } finally {
    await probe.$disconnect().catch(() => undefined);
  }

  const result = await runBattleStatsCollectorExclusive(createCliService);
  const summary = {
    phase: "finished",
    status: result.status,
    reason: result.reason,
    itemCount: result.items.length,
    items: result.items.map((item) => ({
      contentType: item.contentType,
      status: item.status,
      recordCount: item.recordCount,
      errorCode: item.errorCode,
      revision: item.revision,
      // Hash prefix only — full hash is fine in ops logs but keep compact.
      payloadHashPrefix: item.payloadHash?.slice(0, 18),
    })),
  };
  console.info("yshelper_collect", summary);

  if (result.status === "failed" || result.status === "invalid") {
    process.exitCode = 1;
  }
}

main().catch((error: unknown) => {
  let code = "internal_error";
  if (error instanceof BattleStatsCollectorAlreadyRunningError) {
    code = "already_running";
  } else if (error instanceof YshelperAdapterNotConfiguredError) {
    code = "not_configured";
  } else if (error instanceof Error) {
    if (
      error.message === "database_url_invalid" ||
      error.message === "database_url_localhost_rejected" ||
      error.message === "collector_disabled"
    ) {
      code = error.message;
    } else {
      code = error.name || "internal_error";
    }
  }
  console.error("yshelper_collect", { phase: "failed", code });
  process.exit(1);
});
