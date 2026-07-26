import { adaptNativeYshelperPayload } from "./native";
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
 * Kept for fixture / bridge workflows. Live YShelper JSON uses `native-v1`.
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

/**
 * Adapter for confirmed YShelper native JSON (`getAbyssRank*.php`).
 *
 * Selected only when `YSHELPER_ADAPTER_MODE=native-v1`. Kill switches stay
 * independent and default off.
 */
export class NativeV1YshelperAdapter implements YshelperAdapter {
  readonly name = "native-v1";

  adapt(
    contentType: BattleContentType,
    payload: Record<string, unknown>,
  ): NormalizedBattleStats {
    return adaptNativeYshelperPayload(contentType, payload);
  }
}

export function configuredYshelperAdapter(
  env: Environment = process.env,
): YshelperAdapter {
  const mode = env.YSHELPER_ADAPTER_MODE?.trim();
  if (mode === "canonical-v1") {
    return new CanonicalV1YshelperAdapter();
  }
  if (mode === "native-v1") {
    return new NativeV1YshelperAdapter();
  }
  throw new YshelperAdapterNotConfiguredError();
}
