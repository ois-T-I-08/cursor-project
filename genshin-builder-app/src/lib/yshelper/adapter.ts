import { normalizeCanonicalPayload } from "./normalize";
import { parseCanonicalPayload } from "./schema";
import type {
  BattleContentType,
  NormalizedBattleStats,
  YshelperAdapter,
} from "./types";

type Environment = Readonly<Record<string, string | undefined>>;

export class YshelperAdapterNotConfiguredError extends Error {
  constructor() {
    super("yshelper_adapter_not_configured");
    this.name = "YshelperAdapterNotConfiguredError";
  }
}

/**
 * Adapter for an operator-verified canonical-v1 bridge response.
 *
 * The repository has no authoritative YShelper response fixture yet, so this
 * adapter is never selected implicitly and must not be treated as a guessed
 * mapping of YShelper's undocumented fields.
 */
export class CanonicalV1YshelperAdapter implements YshelperAdapter {
  readonly name = "canonical-v1";

  adapt(
    contentType: BattleContentType,
    payload: Record<string, unknown>,
  ): NormalizedBattleStats {
    return normalizeCanonicalPayload(
      contentType,
      parseCanonicalPayload(payload),
    );
  }
}

export function configuredYshelperAdapter(
  env: Environment = process.env,
): YshelperAdapter {
  if (env.YSHELPER_ADAPTER_MODE?.trim() === "canonical-v1") {
    return new CanonicalV1YshelperAdapter();
  }
  throw new YshelperAdapterNotConfiguredError();
}
