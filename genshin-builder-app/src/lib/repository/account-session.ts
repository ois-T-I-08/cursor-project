import "server-only";

import {
  Prisma,
  type Account,
  type PrismaClient,
  type WebSession,
} from "@prisma/client";
import { prisma } from "@/lib/db";
import { AccountSessionError } from "@/lib/auth/errors";

export type WebSessionWithAccount = Prisma.WebSessionGetPayload<{
  include: { account: true };
}>;

export interface WebSessionMetadata {
  readonly deviceLabel: string;
  readonly platform: string;
}

export interface CreateWebSessionRecordInput extends WebSessionMetadata {
  readonly accountId: string;
  readonly tokenHash: string;
  readonly createdAt: Date;
  readonly expiresAt: Date;
}

export interface RotateWebSessionRecordInput extends WebSessionMetadata {
  readonly currentTokenHash: string;
  readonly nextTokenHash: string;
  readonly now: Date;
}

export interface SessionMetadataRecord extends WebSessionMetadata {
  readonly id: string;
  readonly createdAt: Date;
  readonly expiresAt: Date;
  readonly lastSeenAt: Date;
  readonly revokedAt: Date | null;
  readonly rotationCounter: number;
  readonly version: number;
}

export interface AccountSessionRepository {
  transaction<T>(
    operation: (repository: AccountSessionRepository) => Promise<T>,
  ): Promise<T>;
  createAccount(): Promise<Account>;
  findActiveAccount(accountId: string): Promise<Account | null>;
  createSession(input: CreateWebSessionRecordInput): Promise<WebSession>;
  resolveSessionByTokenHash(
    tokenHash: string,
  ): Promise<WebSessionWithAccount | null>;
  rotateSession(
    input: RotateWebSessionRecordInput,
  ): Promise<WebSessionWithAccount>;
  revokeSession(accountId: string, sessionId: string, now: Date): Promise<number>;
  revokeAllSessions(accountId: string, now: Date): Promise<number>;
  touchSessionLastSeen(
    sessionId: string,
    observedLastSeenAt: Date,
    now: Date,
  ): Promise<boolean>;
  cleanupExpiredSessions(cutoff: Date, limit?: number): Promise<number>;
  listSessionMetadata(accountId: string): Promise<SessionMetadataRecord[]>;
}

type AccountSessionDb = Pick<
  Prisma.TransactionClient,
  "account" | "webSession"
>;

const DEFAULT_DB_ATTEMPTS = 3;

export class PrismaAccountSessionRepository
  implements AccountSessionRepository
{
  constructor(
    private readonly db: AccountSessionDb = prisma,
    private readonly transactionRoot: PrismaClient | null = prisma,
  ) {}

  async transaction<T>(
    operation: (repository: AccountSessionRepository) => Promise<T>,
  ): Promise<T> {
    if (!this.transactionRoot) return operation(this);
    return withFiniteDbRetry(() =>
      this.transactionRoot!.$transaction(
        (transaction) =>
          operation(new PrismaAccountSessionRepository(transaction, null)),
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      ),
    );
  }

  createAccount(): Promise<Account> {
    // No input object is accepted: id/status/version are always server-managed.
    return this.db.account.create({ data: {} });
  }

  findActiveAccount(accountId: string): Promise<Account | null> {
    return this.db.account.findFirst({
      where: {
        id: accountId,
        status: "active",
        disabledAt: null,
        deletionRequestedAt: null,
      },
    });
  }

  async createSession(
    input: CreateWebSessionRecordInput,
  ): Promise<WebSession> {
    return this.atomic((repository) => repository.createSessionRows(input));
  }

  resolveSessionByTokenHash(
    tokenHash: string,
  ): Promise<WebSessionWithAccount | null> {
    return this.db.webSession.findUnique({
      where: { tokenHash },
      include: { account: true },
    });
  }

  async rotateSession(
    input: RotateWebSessionRecordInput,
  ): Promise<WebSessionWithAccount> {
    return this.atomic(async (repository) => {
      const current = await repository.db.webSession.findUnique({
        where: { tokenHash: input.currentTokenHash },
        include: { account: true },
      });
      if (!current) throw new AccountSessionError("invalidSession");
      assertUsableForRotation(current, input.now);

      const replacement = await repository.db.webSession.create({
        data: {
          accountId: current.accountId,
          tokenHash: input.nextTokenHash,
          createdAt: input.now,
          expiresAt: current.expiresAt,
          lastSeenAt: input.now,
          rotationCounter: current.rotationCounter + 1,
          version: current.version + 1,
          accountVersion: current.account.version,
          deviceLabel: input.deviceLabel,
          platform: input.platform,
        },
      });

      const revoked = await repository.db.webSession.updateMany({
        where: {
          id: current.id,
          version: current.version,
          revokedAt: null,
          replacedBySessionId: null,
          expiresAt: { gt: input.now },
          accountVersion: current.account.version,
        },
        data: {
          revokedAt: input.now,
          replacedBySessionId: replacement.id,
          version: { increment: 1 },
        },
      });
      if (revoked.count !== 1) {
        throw new AccountSessionError("rotationConflict");
      }

      return { ...replacement, account: current.account };
    });
  }

  async revokeSession(
    accountId: string,
    sessionId: string,
    now: Date,
  ): Promise<number> {
    const result = await this.db.webSession.updateMany({
      where: { id: sessionId, accountId, revokedAt: null },
      data: { revokedAt: now, version: { increment: 1 } },
    });
    return result.count;
  }

  async revokeAllSessions(accountId: string, now: Date): Promise<number> {
    return this.atomic(async (repository) => {
      const account = await repository.db.account.updateMany({
        where: {
          id: accountId,
          status: "active",
          disabledAt: null,
          deletionRequestedAt: null,
        },
        data: { version: { increment: 1 } },
      });
      if (account.count !== 1) {
        throw new AccountSessionError("accountDisabled");
      }
      const sessions = await repository.db.webSession.updateMany({
        where: { accountId, revokedAt: null },
        data: { revokedAt: now, version: { increment: 1 } },
      });
      return sessions.count;
    });
  }

  async touchSessionLastSeen(
    sessionId: string,
    observedLastSeenAt: Date,
    now: Date,
  ): Promise<boolean> {
    const result = await this.db.webSession.updateMany({
      where: {
        id: sessionId,
        lastSeenAt: observedLastSeenAt,
        revokedAt: null,
        expiresAt: { gt: now },
      },
      data: { lastSeenAt: now },
    });
    return result.count === 1;
  }

  async cleanupExpiredSessions(cutoff: Date, limit = 500): Promise<number> {
    const boundedLimit = Math.max(1, Math.min(1_000, Math.trunc(limit)));
    const expired = await this.db.webSession.findMany({
      where: { expiresAt: { lte: cutoff } },
      select: { id: true },
      orderBy: { expiresAt: "asc" },
      take: boundedLimit,
    });
    if (expired.length === 0) return 0;
    const removed = await this.db.webSession.deleteMany({
      where: { id: { in: expired.map(({ id }) => id) }, expiresAt: { lte: cutoff } },
    });
    return removed.count;
  }

  listSessionMetadata(accountId: string): Promise<SessionMetadataRecord[]> {
    return this.db.webSession.findMany({
      where: { accountId },
      select: {
        id: true,
        deviceLabel: true,
        platform: true,
        createdAt: true,
        expiresAt: true,
        lastSeenAt: true,
        revokedAt: true,
        rotationCounter: true,
        version: true,
      },
      orderBy: { lastSeenAt: "desc" },
    });
  }

  private async atomic<T>(
    operation: (repository: PrismaAccountSessionRepository) => Promise<T>,
  ): Promise<T> {
    if (!this.transactionRoot) return operation(this);
    return this.transaction((repository) =>
      operation(repository as PrismaAccountSessionRepository),
    );
  }

  private async createSessionRows(
    input: CreateWebSessionRecordInput,
  ): Promise<WebSession> {
    const account = await this.findActiveAccount(input.accountId);
    if (!account) throw new AccountSessionError("accountDisabled");
    return this.db.webSession.create({
      data: {
        accountId: account.id,
        tokenHash: input.tokenHash,
        createdAt: input.createdAt,
        expiresAt: input.expiresAt,
        lastSeenAt: input.createdAt,
        rotationCounter: 0,
        version: 1,
        accountVersion: account.version,
        deviceLabel: input.deviceLabel,
        platform: input.platform,
      },
    });
  }
}

function assertUsableForRotation(
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

export async function withFiniteDbRetry<T>(
  operation: () => Promise<T>,
  maxAttempts = DEFAULT_DB_ATTEMPTS,
): Promise<T> {
  const attempts = Math.max(1, Math.min(5, Math.trunc(maxAttempts)));
  let lastError: unknown;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (!isRetryableTransactionError(error)) throw error;
    }
  }
  throw new AccountSessionError("retryExhausted", {
    retryable: true,
    cause: lastError,
  });
}

export function isRetryableTransactionError(error: unknown): boolean {
  return prismaErrorCode(error) === "P2034";
}

export function isUniqueConstraintError(error: unknown): boolean {
  return prismaErrorCode(error) === "P2002";
}

function prismaErrorCode(error: unknown): string | null {
  if (typeof error !== "object" || error === null || !("code" in error)) {
    return null;
  }
  const code = (error as { code?: unknown }).code;
  return typeof code === "string" ? code : null;
}
