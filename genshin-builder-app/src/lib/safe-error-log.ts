/**
 * Log failures without dumping Error objects that may embed URLs, headers,
 * or connection strings (e.g. Prisma / fetch).
 */
export function logSafeFailure(
  scope: string,
  code: string,
  extras: Record<string, string | number | boolean | null | undefined> = {},
): void {
  const safeExtras = Object.fromEntries(
    Object.entries(extras).filter(([, value]) => value != null),
  );
  console.error(`[${scope}]`, { code, ...safeExtras });
}
