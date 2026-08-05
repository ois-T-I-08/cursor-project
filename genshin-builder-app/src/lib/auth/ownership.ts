import "server-only";

import { AccountSessionError } from "./errors";

const SERVER_OWNED_FIELDS = new Set([
  "ownerid",
  "accountid",
  "userid",
  "sessionid",
  "deviceid",
  "clientscope",
  "tokenhash",
  "status",
  "version",
  "__proto__",
  "prototype",
  "constructor",
]);

/** Strict DTO parserの前段でserver-owned fieldの注入をfail-closedにする。 */
export function assertNoClientOwnershipFields(value: unknown): void {
  const visited = new WeakSet<object>();
  inspect(value, visited, 0);
}

function inspect(value: unknown, visited: WeakSet<object>, depth: number): void {
  if (depth > 16 || value === null || typeof value !== "object") return;
  if (visited.has(value)) return;
  visited.add(value);

  if (Array.isArray(value)) {
    for (const item of value) inspect(item, visited, depth + 1);
    return;
  }

  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (SERVER_OWNED_FIELDS.has(key.toLowerCase())) {
      throw new AccountSessionError("clientOwnershipForbidden");
    }
    inspect(child, visited, depth + 1);
  }
}
