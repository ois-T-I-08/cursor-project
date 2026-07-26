import "server-only";

import {
  authorizeBearerSecret,
  authorizationHttpStatus,
  type AdminAuthorization,
} from "@/lib/admin/bearer-auth";
import { allowAdminRequest } from "@/lib/admin/rate-limit";

export type { AdminAuthorization };
export { authorizationHttpStatus };

export function authorizeBuildGuideAdminRequest(request: Request): AdminAuthorization {
  return authorizeBearerSecret(request, "BUILD_GUIDE_ADMIN_SECRET");
}

export function allowBuildGuideAdminRequest(request: Request, now = Date.now()): boolean {
  return allowAdminRequest(request, "build-guides", now);
}
