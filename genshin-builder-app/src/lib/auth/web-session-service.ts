import "server-only";

import type { WebSession } from "@prisma/client";
import {
  type AccountSessionRepository,
  isUniqueConstraintError,
  PrismaAccountSessionRepository,
  type SessionMetadataRecord,
  type WebSessionMetadata,
  type WebSessionWithAccount,
} from "@/lib/repository/account-session";
import {
  NOOP_AUTH_AUDIT_SINK,
  recordAuthAuditSafely,
  type AuthAuditSink,
} from "./audit";
import { AccountSessionError, safeAccountSessionErrorCode } from "./errors";
import {
  accountIdentityFeatureState,
  isWebSessionIssuanceEnabled,
  type AccountIdentityFeatureState,
} from "./feature-flags";
import {
  correlationValue,
  generateOpaqueToken,
  hashOpaqueToken,
} from "./tokens";

export const WEB_SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1_000;
export const LAST_SEEN_WRITE_INTERVAL_MS = 5 * 60 * 1_000;
const TOKEN_CREATION_ATTEMPTS = 3;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SAFE_PLATFORMS = new Set([
  "web",
  "windows",
  "macos",
  "linux",
  "ios",
  "android",
  "unknown",
]);

export interface ResolvedAccountSession {
  readonly accountId: string;
  readonly sessionId: string;
  readonly sessionVersion: number;
  readonly issuedAt: Date;
  readonly expiresAt: Date;
  readonly authenticationLevel: "session";
}

export interface IssuedWebSession extends ResolvedAccountSession {
  /** Cookieへ一度だけ渡すraw token。DB/audit/logへ渡してはならない。 */
  readonly rawToken: string;
}

export interface WebSessionService {
  issueSessionForVerifiedAccount(
    accountId: string,
    metadata?: Partial<WebSessionMetadata>,
  ): Promise<IssuedWebSession>;
  resolveSession(rawToken: string): Promise<ResolvedAccountSession>;
  rotateSession(
    rawToken: string,
    metadata?: Partial<WebSessionMetadata>,
  ): Promise<IssuedWebSession>;
  revokeSession(context: ResolvedAccountSession): Promise<number>;
  revokeAllAccountSessions(context: ResolvedAccountSession): Promise<number>;
  listSessionMetadata(
    context: ResolvedAccountSession,
  ): Promise<SessionMetadataRecord[]>;
  cleanupExpiredSessions(cutoff?: Date, limit?: number): Promise<number>;
}

export interface WebSessionServiceOptions {
  readonly repository?: AccountSessionRepository;
  readonly audit?: AuthAuditSink;
  readonly now?: () => Date;
  readonly tokenFactory?: () => string;
  readonly featureState?: () => AccountIdentityFeatureState;
}

export function createWebSessionService(
  options: WebSessionServiceOptions = {},
): WebSessionService {
  const repository = options.repository ?? new PrismaAccountSessionRepository();
  const audit = options.audit ?? NOOP_AUTH_AUDIT_SINK;
  const now = options.now ?? (() => new Date());
  const tokenFactory = options.tokenFactory ?? generateOpaqueToken;
  const featureState = options.featureState ?? accountIdentityFeatureState;

  async function issueSessionForVerifiedAccount(
    accountId: string,
    metadata: Partial<WebSessionMetadata> = {},
  ): Promise<IssuedWebSession> {
    const occurredAt = now();
    try {
      assertIssuanceEnabled(featureState());
      if (!UUID_PATTERN.test(accountId)) {
        throw new AccountSessionError("accountDisabled");
      }
      const safeMetadata = sanitizeSessionMetadata(metadata);
      const expiresAt = new Date(occurredAt.getTime() + WEB_SESSION_TTL_MS);

      for (let attempt = 1; attempt <= TOKEN_CREATION_ATTEMPTS; attempt++) {
        const rawToken = tokenFactory();
        const tokenHash = hashOpaqueToken(rawToken);
        try {
          const session = await repository.createSession({
            accountId,
            tokenHash,
            createdAt: occurredAt,
            expiresAt,
            ...safeMetadata,
          });
          await auditSuccess("sessionIssued", accountId, session, occurredAt);
          return issued(rawToken, session);
        } catch (error) {
          if (isUniqueConstraintError(error)) {
            if (attempt < TOKEN_CREATION_ATTEMPTS) continue;
            throw new AccountSessionError("retryExhausted", {
              retryable: true,
            });
          }
          throw error;
        }
      }
      throw new AccountSessionError("retryExhausted", { retryable: true });
    } catch (error) {
      await auditFailure("sessionIssued", occurredAt, error);
      throw normalizeError(error);
    }
  }

  async function resolveSession(rawToken: string): Promise<ResolvedAccountSession> {
    const occurredAt = now();
    let record: WebSessionWithAccount | null = null;
    try {
      const tokenHash = hashOpaqueToken(rawToken);
      record = await repository.resolveSessionByTokenHash(tokenHash);
      if (!record) throw new AccountSessionError("invalidSession");
      assertSessionIsActive(record, occurredAt);

      if (
        occurredAt.getTime() - record.lastSeenAt.getTime() >=
        LAST_SEEN_WRITE_INTERVAL_MS
      ) {
        await repository.touchSessionLastSeen(
          record.id,
          record.lastSeenAt,
          occurredAt,
        );
      }
      await auditSuccess("sessionResolved", record.accountId, record, occurredAt);
      return resolved(record);
    } catch (error) {
      await auditFailure(
        "sessionResolved",
        occurredAt,
        error,
        record?.accountId,
        record?.id,
      );
      throw normalizeError(error);
    }
  }

  async function rotateSession(
    rawToken: string,
    metadata: Partial<WebSessionMetadata> = {},
  ): Promise<IssuedWebSession> {
    const occurredAt = now();
    try {
      assertIssuanceEnabled(featureState());
      const currentTokenHash = hashOpaqueToken(rawToken);
      const safeMetadata = sanitizeSessionMetadata(metadata);

      for (let attempt = 1; attempt <= TOKEN_CREATION_ATTEMPTS; attempt++) {
        const nextRawToken = tokenFactory();
        const nextTokenHash = hashOpaqueToken(nextRawToken);
        try {
          const replacement = await repository.rotateSession({
            currentTokenHash,
            nextTokenHash,
            now: occurredAt,
            ...safeMetadata,
          });
          await auditSuccess(
            "sessionRotated",
            replacement.accountId,
            replacement,
            occurredAt,
          );
          return issued(nextRawToken, replacement);
        } catch (error) {
          if (isUniqueConstraintError(error)) {
            if (attempt < TOKEN_CREATION_ATTEMPTS) continue;
            throw new AccountSessionError("retryExhausted", {
              retryable: true,
            });
          }
          throw error;
        }
      }
      throw new AccountSessionError("retryExhausted", { retryable: true });
    } catch (error) {
      await auditFailure("sessionRotated", occurredAt, error);
      throw normalizeError(error);
    }
  }

  async function revokeSession(
    context: ResolvedAccountSession,
  ): Promise<number> {
    const occurredAt = now();
    try {
      const affected = await repository.revokeSession(
        context.accountId,
        context.sessionId,
        occurredAt,
      );
      await recordAuthAuditSafely(audit, {
        operation: "sessionRevoked",
        outcome: "ok",
        occurredAt,
        accountCorrelation: correlationValue(context.accountId),
        sessionCorrelation: correlationValue(context.sessionId),
        affectedCount: affected,
      });
      return affected;
    } catch (error) {
      await auditFailure(
        "sessionRevoked",
        occurredAt,
        error,
        context.accountId,
        context.sessionId,
      );
      throw normalizeError(error);
    }
  }

  async function revokeAllAccountSessions(
    context: ResolvedAccountSession,
  ): Promise<number> {
    const occurredAt = now();
    try {
      const affected = await repository.revokeAllSessions(
        context.accountId,
        occurredAt,
      );
      await recordAuthAuditSafely(audit, {
        operation: "accountSessionsRevoked",
        outcome: "ok",
        occurredAt,
        accountCorrelation: correlationValue(context.accountId),
        affectedCount: affected,
      });
      return affected;
    } catch (error) {
      await auditFailure(
        "accountSessionsRevoked",
        occurredAt,
        error,
        context.accountId,
      );
      throw normalizeError(error);
    }
  }

  return {
    issueSessionForVerifiedAccount,
    resolveSession,
    rotateSession,
    revokeSession,
    revokeAllAccountSessions,
    listSessionMetadata: (context) =>
      repository.listSessionMetadata(context.accountId),
    cleanupExpiredSessions: (cutoff = now(), limit) =>
      repository.cleanupExpiredSessions(cutoff, limit),
  };

  async function auditSuccess(
    operation: "sessionIssued" | "sessionResolved" | "sessionRotated",
    accountId: string,
    session: Pick<WebSession, "id">,
    occurredAt: Date,
  ): Promise<void> {
    await recordAuthAuditSafely(audit, {
      operation,
      outcome: "ok",
      occurredAt,
      accountCorrelation: correlationValue(accountId),
      sessionCorrelation: correlationValue(session.id),
    });
  }

  async function auditFailure(
    operation:
      | "sessionIssued"
      | "sessionResolved"
      | "sessionRotated"
      | "sessionRevoked"
      | "accountSessionsRevoked",
    occurredAt: Date,
    error: unknown,
    accountId?: string,
    sessionId?: string,
  ): Promise<void> {
    await recordAuthAuditSafely(audit, {
      operation,
      outcome: "rejected",
      occurredAt,
      safeErrorCode: safeAccountSessionErrorCode(error),
      ...(accountId
        ? { accountCorrelation: correlationValue(accountId) }
        : {}),
      ...(sessionId
        ? { sessionCorrelation: correlationValue(sessionId) }
        : {}),
    });
  }
}

export const webSessionService = createWebSessionService();

function assertIssuanceEnabled(state: AccountIdentityFeatureState): void {
  if (!isWebSessionIssuanceEnabled(state)) {
    throw new AccountSessionError("featureDisabled");
  }
}

function assertSessionIsActive(
  session: WebSessionWithAccount,
  now: Date,
): void {
  if (session.revokedAt) throw new AccountSessionError("sessionRevoked");
  if (session.expiresAt.getTime() <= now.getTime()) {
    throw new AccountSessionError("sessionExpired");
  }
  if (
    session.account.status !== "active" ||
    session.account.disabledAt !== null ||
    session.account.deletionRequestedAt !== null ||
    session.accountVersion !== session.account.version
  ) {
    throw new AccountSessionError("accountDisabled");
  }
}

function sanitizeSessionMetadata(
  metadata: Partial<WebSessionMetadata>,
): WebSessionMetadata {
  const label = String(metadata.deviceLabel ?? "")
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 80);
  const requestedPlatform = String(metadata.platform ?? "web").toLowerCase();
  return {
    deviceLabel: label,
    platform: SAFE_PLATFORMS.has(requestedPlatform)
      ? requestedPlatform
      : "unknown",
  };
}

function issued(rawToken: string, session: WebSession): IssuedWebSession {
  return { rawToken, ...resolved(session) };
}

function resolved(
  session: Pick<
    WebSession,
    "accountId" | "id" | "version" | "createdAt" | "expiresAt"
  >,
): ResolvedAccountSession {
  return {
    accountId: session.accountId,
    sessionId: session.id,
    sessionVersion: session.version,
    authenticationLevel: "session",
    issuedAt: session.createdAt,
    expiresAt: session.expiresAt,
  };
}

function normalizeError(error: unknown): AccountSessionError {
  if (error instanceof AccountSessionError) return error;
  return new AccountSessionError("temporarilyUnavailable");
}
