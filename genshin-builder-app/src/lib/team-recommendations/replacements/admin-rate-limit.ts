import "server-only";

import {
  allowAdminRequest,
  resetAdminRateLimitForTest,
} from "@/lib/admin/rate-limit";

const SCOPE = "team-templates";

export function allowTemplateAdminRequest(request: Request, now = Date.now()): boolean {
  return allowAdminRequest(request, SCOPE, now);
}

export function resetTemplateAdminRateLimitForTest(): void {
  resetAdminRateLimitForTest(SCOPE);
}
