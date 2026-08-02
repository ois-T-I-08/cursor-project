import "server-only";

import {
  authorizeBearerSecret,
  type AdminAuthorization,
} from "@/lib/admin/bearer-auth";

export type { AdminAuthorization };

/** Backward-compatible wrapper; secret name remains TEAM_TEMPLATE_ADMIN_SECRET. */
export function authorizeTemplateAdminRequest(request: Request): AdminAuthorization {
  return authorizeBearerSecret(request, "TEAM_TEMPLATE_ADMIN_SECRET");
}
