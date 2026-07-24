import { fetchJsonObject } from "@/lib/api/safe-json-fetch";
import type { BattleContentType, YshelperTransport } from "./types";

const DEFAULT_TIMEOUT_MS = 15_000;
const DEFAULT_MAX_BYTES = 4 * 1024 * 1024;
type Environment = Readonly<Record<string, string | undefined>>;

export class YshelperClientConfigurationError extends Error {
  constructor() {
    super("yshelper_client_not_configured");
    this.name = "YshelperClientConfigurationError";
  }
}

export class YshelperHttpClient implements YshelperTransport {
  constructor(
    private readonly options: {
      fetchImpl?: typeof fetch;
      env?: Environment;
    } = {},
  ) {}

  async fetch(
    contentType: BattleContentType,
  ): Promise<Record<string, unknown>> {
    const env = this.options.env ?? process.env;
    const url = resolveEndpoint(contentType, env);
    const token = env.YSHELPER_API_TOKEN?.trim();
    return await fetchJsonObject(url, {
      timeoutMs: boundedInteger(
        env.YSHELPER_REQUEST_TIMEOUT_MS,
        DEFAULT_TIMEOUT_MS,
        1_000,
        60_000,
      ),
      maxBytes: boundedInteger(
        env.YSHELPER_MAX_RESPONSE_BYTES,
        DEFAULT_MAX_BYTES,
        1_024,
        16 * 1024 * 1024,
      ),
      retries: 1,
      requireJsonContentType: true,
      fetchImpl: this.options.fetchImpl,
      headers: {
        Accept: "application/json",
        "User-Agent": "genshin-builder/yshelper-collector",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
    });
  }
}

export function resolveEndpoint(
  contentType: BattleContentType,
  env: Environment = process.env,
): string {
  const baseValue = env.YSHELPER_API_BASE_URL?.trim();
  const endpointValue =
    contentType === "abyss"
      ? env.YSHELPER_ABYSS_ENDPOINT?.trim()
      : env.YSHELPER_STYGIAN_ENDPOINT?.trim();
  if (!baseValue || !endpointValue) {
    throw new YshelperClientConfigurationError();
  }

  let base: URL;
  let endpoint: URL;
  try {
    base = new URL(baseValue);
    endpoint = new URL(endpointValue, base);
  } catch {
    throw new YshelperClientConfigurationError();
  }
  if (
    base.protocol !== "https:" ||
    base.username ||
    base.password ||
    base.pathname !== "/" ||
    base.search ||
    base.hash ||
    !endpointValue.startsWith("/") ||
    endpointValue.startsWith("//") ||
    endpoint.origin !== base.origin ||
    endpoint.username ||
    endpoint.password ||
    endpoint.search ||
    endpoint.hash ||
    endpoint.pathname !== endpointValue
  ) {
    throw new YshelperClientConfigurationError();
  }
  return endpoint.toString();
}

function boundedInteger(
  raw: string | undefined,
  fallback: number,
  min: number,
  max: number,
): number {
  const value = Number(raw);
  return Number.isSafeInteger(value) && value >= min && value <= max
    ? value
    : fallback;
}
