import { stableHash } from "../cache-key";
import type { ReplacementCacheIdentity } from "./types";

export function replacementCacheKey(identity: ReplacementCacheIdentity): string {
  return stableHash(identity);
}
