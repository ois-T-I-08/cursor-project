import { prisma } from "@/lib/db";
import type { AbyssStatistics } from "./types";

const CACHE_KEY = "abyss-statistics:latest";

export interface AbyssStatisticsCacheStore {
  read(): Promise<AbyssStatistics | null>;
  write(value: AbyssStatistics): Promise<void>;
}

export class PrismaAbyssStatisticsCacheStore
  implements AbyssStatisticsCacheStore
{
  async read(): Promise<AbyssStatistics | null> {
    const row = await prisma.externalApiCache.findUnique({
      where: { cacheKey: CACHE_KEY },
    });
    if (row === null) return null;
    try {
      const parsed: unknown = JSON.parse(row.payload);
      return isCachedStatistics(parsed) ? parsed : null;
    } catch {
      return null;
    }
  }

  async write(value: AbyssStatistics): Promise<void> {
    await prisma.externalApiCache.upsert({
      where: { cacheKey: CACHE_KEY },
      create: {
        cacheKey: CACHE_KEY,
        source: value.metadata.source,
        version: value.version.sourceApiVersion,
        sampleSize: value.metadata.sampleSize,
        payload: JSON.stringify(value),
        fetchedAt: new Date(value.metadata.fetchedAt),
        expiresAt: new Date(value.metadata.expiresAt),
      },
      update: {
        source: value.metadata.source,
        version: value.version.sourceApiVersion,
        sampleSize: value.metadata.sampleSize,
        payload: JSON.stringify(value),
        fetchedAt: new Date(value.metadata.fetchedAt),
        expiresAt: new Date(value.metadata.expiresAt),
      },
    });
  }
}

function isCachedStatistics(value: unknown): value is AbyssStatistics {
  if (!isObject(value)) return false;
  if (!isObject(value.version) || !isObject(value.metadata)) return false;
  if (!Array.isArray(value.characters) || !Array.isArray(value.teams)) {
    return false;
  }
  const metadata = value.metadata;
  return (
    metadata.source === "AZA.GG" &&
    isIsoDate(metadata.fetchedAt) &&
    isIsoDate(metadata.expiresAt) &&
    isIsoDate(metadata.sourceUpdatedAt) &&
    typeof metadata.sampleSize === "number" &&
    Number.isSafeInteger(metadata.sampleSize) &&
    metadata.sampleSize >= 0 &&
    value.characters.length <= 256 &&
    value.teams.length <= 400
  );
}

function isIsoDate(value: unknown): value is string {
  return typeof value === "string" && !Number.isNaN(Date.parse(value));
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
