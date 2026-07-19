import { fetchJsonObject, UpstreamFetchError } from "@/lib/api/safe-json-fetch";
import type { AbyssStatisticsSnapshot } from "@/lib/abyss/types";
import { AbyssStatisticsError } from "./errors";
import { normalizeAzaAbyssStatistics } from "./normalize-aza";
import type { AbyssStatisticsProvider } from "./provider";

const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
const DEFAULT_TIMEOUT_MS = 10_000;
const KNOWN_AZA_API_VERSIONS = new Set(["5.6"]);

type SafeFetch = typeof fetchJsonObject;
type AzaEnvironment = Readonly<Record<string, string | undefined>>;
type AzaVersionLogDetails = {
  sourceApiVersion: string;
  scheduleId?: number;
  itemCount?: number;
  invalidField?: string;
};
type AzaVersionLogger = (
  event: string,
  details: AzaVersionLogDetails,
) => void;

export class AzaAbyssStatisticsProvider
  implements AbyssStatisticsProvider
{
  readonly name = "AZA.GG";

  constructor(
    private readonly safeFetch: SafeFetch = fetchJsonObject,
    private readonly environment: AzaEnvironment = process.env,
    private readonly versionLogger: AzaVersionLogger = defaultVersionLogger,
  ) {}

  async fetchStatistics(): Promise<AbyssStatisticsSnapshot> {
    const baseUrl = this.environment.AZA_API_BASE_URL?.trim();
    if (!baseUrl) throw new AbyssStatisticsError("notConfigured");

    let url: URL;
    try {
      url = new URL("/kv/read", baseUrl);
    } catch {
      throw new AbyssStatisticsError("notConfigured");
    }
    if (url.protocol !== "https:") {
      throw new AbyssStatisticsError("notConfigured");
    }
    url.searchParams.set("key_id", "genshin_abyss_statistics");

    try {
      const input = await this.safeFetch(url.toString(), {
        timeoutMs: readTimeout(this.environment.AZA_REQUEST_TIMEOUT_MS),
        maxBytes: MAX_RESPONSE_BYTES,
        retries: 1,
        headers: {
          Accept: "application/json",
          "User-Agent":
            "GenshinBuilder-Web/0.1 (AZA.GG statistics proxy)",
        },
      });
      const identity = readAzaResponseIdentity(input);
      try {
        const snapshot = normalizeAzaAbyssStatistics(input);
        if (!KNOWN_AZA_API_VERSIONS.has(snapshot.version.sourceApiVersion)) {
          this.versionLogger("unknown_api_version_schema_compatible", {
            sourceApiVersion: snapshot.version.sourceApiVersion,
            scheduleId: snapshot.version.scheduleId,
            itemCount: snapshot.characters.length + snapshot.teams.length,
          });
        }
        return snapshot;
      } catch (error) {
        if (
          identity.sourceApiVersion !== undefined &&
          !KNOWN_AZA_API_VERSIONS.has(identity.sourceApiVersion)
        ) {
          this.versionLogger("unknown_api_version_schema_invalid", {
            sourceApiVersion: identity.sourceApiVersion,
            ...(identity.scheduleId === undefined
              ? {}
              : { scheduleId: identity.scheduleId }),
            ...(identity.itemCount === undefined
              ? {}
              : { itemCount: identity.itemCount }),
            invalidField: "schema",
          });
        }
        throw error;
      }
    } catch (error) {
      if (error instanceof AbyssStatisticsError) throw error;
      if (error instanceof UpstreamFetchError) {
        if (error.code === "timeout") {
          throw new AbyssStatisticsError("timeout");
        }
        if (error.code === "httpStatus" && error.status === 429) {
          throw new AbyssStatisticsError("rateLimited", 429);
        }
        if (
          error.code === "invalidJson" ||
          error.code === "invalidData" ||
          error.code === "invalidEncoding" ||
          error.code === "bodyTooLarge"
        ) {
          throw new AbyssStatisticsError("invalidResponse");
        }
        throw new AbyssStatisticsError("networkError", error.status);
      }
      throw new AbyssStatisticsError("unknownError");
    }
  }
}

function readAzaResponseIdentity(input: Record<string, unknown>): {
  sourceApiVersion?: string;
  scheduleId?: number;
  itemCount?: number;
} {
  const meta = record(input.meta);
  const data = record(input.data);
  const schedule = record(data?.schedule);
  const sourceApiVersion = typeof meta?.api_ver === "string" &&
      /^[A-Za-z0-9._-]{1,32}$/.test(meta.api_ver)
    ? meta.api_ver
    : undefined;
  const scheduleId = typeof schedule?.id === "number" &&
      Number.isSafeInteger(schedule.id)
    ? schedule.id
    : undefined;
  const characters = record(data?.character);
  const party = record(data?.party);
  const upperTeams = Array.isArray(party?.["1"]) ? party["1"].length : 0;
  const lowerTeams = Array.isArray(party?.["2"]) ? party["2"].length : 0;
  const itemCount = characters === undefined
    ? undefined
    : Object.keys(characters).length + upperTeams + lowerTeams;
  return { sourceApiVersion, scheduleId, itemCount };
}

function record(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function defaultVersionLogger(
  event: string,
  details: AzaVersionLogDetails,
): void {
  console.warn("abyss_statistics", { event, ...details });
}

function readTimeout(value: string | undefined): number {
  if (value === undefined || value.trim() === "") return DEFAULT_TIMEOUT_MS;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1_000 || parsed > 30_000) {
    throw new AbyssStatisticsError("notConfigured");
  }
  return parsed;
}
