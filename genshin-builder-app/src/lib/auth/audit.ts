import "server-only";

import type { AccountSessionErrorCode } from "./errors";

export type AuthAuditOperation =
  | "sessionIssued"
  | "sessionResolved"
  | "sessionRotated"
  | "sessionRevoked"
  | "accountSessionsRevoked";

export interface AuthAuditEvent {
  readonly operation: AuthAuditOperation;
  readonly outcome: "ok" | "rejected" | "error";
  readonly occurredAt: Date;
  readonly accountCorrelation?: string;
  readonly sessionCorrelation?: string;
  readonly safeErrorCode?: AccountSessionErrorCode;
  readonly affectedCount?: number;
}

/**
 * Durable audit保存はretention/access policy決定後の別PR。
 * このinterfaceはtoken/Cookie/subject/emailを受け取れない最小call pointだけを固定する。
 */
export interface AuthAuditSink {
  record(event: AuthAuditEvent): Promise<void>;
}

export const NOOP_AUTH_AUDIT_SINK: AuthAuditSink = {
  async record(): Promise<void> {},
};

export async function recordAuthAuditSafely(
  sink: AuthAuditSink,
  event: AuthAuditEvent,
): Promise<void> {
  try {
    await sink.record(event);
  } catch {
    // Audit implementation is intentionally absent in this foundation PR.
    // Never log the event or original error because future sinks may hold sensitive context.
  }
}
