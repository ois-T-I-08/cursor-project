import type { PrismaClient } from "@prisma/client";

export type DryRunDbLoadResult =
  | { ok: true; ids: Set<string> }
  | {
      ok: false;
      code: string | null;
      name: string;
      message: string;
    };

export function sanitizePrismaMessage(message: string): string {
  return message
    .replace(/postgresql:\/\/[^@\s]+@/gi, "postgresql://***@")
    .replace(/[A-Za-z0-9+/=_-]{24,}/g, "***")
    .replace(/localhost:\d+/g, "localhost:***")
    .slice(0, 240);
}

export function hostKindFromDatabaseUrl(
  raw: string | undefined,
): "missing" | "neon-pooler" | "neon-non-pooler" | "localhost" | "other" | "parse-error" {
  if (!raw) return "missing";
  try {
    const host = new URL(raw).hostname.toLowerCase();
    if (host.endsWith(".neon.tech")) {
      return host.includes("-pooler") ? "neon-pooler" : "neon-non-pooler";
    }
    if (host === "localhost" || host === "127.0.0.1") return "localhost";
    return "other";
  } catch {
    return "parse-error";
  }
}

export function missingCharacterIds(
  publishedIds: readonly string[],
  knownIds: ReadonlySet<string>,
): string[] {
  return [...new Set(publishedIds)]
    .filter((id) => !knownIds.has(id))
    .sort((a, b) => a.localeCompare(b));
}

export async function loadKnownCharacterIds(
  prisma: PrismaClient,
): Promise<DryRunDbLoadResult> {
  try {
    const rows = await prisma.character.findMany({ select: { id: true } });
    return { ok: true, ids: new Set(rows.map((row) => row.id)) };
  } catch (error) {
    const err = error as { name?: string; code?: string; message?: string };
    return {
      ok: false,
      code: err.code ?? null,
      name: err.name ?? "Error",
      message: sanitizePrismaMessage(String(err.message ?? "")),
    };
  }
}

export function parseRequireDb(
  argv: readonly string[],
  env: Readonly<Record<string, string | undefined>>,
): boolean {
  if (argv.includes("--require-db")) return true;
  return env.YSHELPER_DRY_RUN_REQUIRE_DB?.trim().toLowerCase() === "true";
}
