import { randomUUID } from "node:crypto";
import type { Account, WebSession } from "@prisma/client";
import { describe, expect, it, vi } from "vitest";
import type { AuthAuditEvent, AuthAuditSink } from "@/lib/auth/audit";
import {
  buildWebSessionCookie,
  buildWebSessionDeletionCookie,
  parseWebSessionCookie,
  WEB_SESSION_COOKIE_NAME,
} from "@/lib/auth/cookies";
import { resolveAuthContext } from "@/lib/auth/auth-context";
import {
  AccountSessionError,
  safeAccountSessionErrorCode,
} from "@/lib/auth/errors";
import {
  accountIdentityFeatureState,
  isWebSessionIssuanceEnabled,
} from "@/lib/auth/feature-flags";
import { assertNoClientOwnershipFields } from "@/lib/auth/ownership";
import {
  generateOpaqueToken,
  hashOpaqueToken,
  isValidOpaqueToken,
  OPAQUE_TOKEN_BYTES,
} from "@/lib/auth/tokens";
import {
  createWebSessionService,
  type WebSessionService,
} from "@/lib/auth/web-session-service";
import type {
  AccountSessionRepository,
  CreateWebSessionRecordInput,
  RotateWebSessionRecordInput,
  SessionMetadataRecord,
  WebSessionWithAccount,
} from "@/lib/repository/account-session";
import { withFiniteDbRetry } from "@/lib/repository/account-session";

const ENABLED = () => ({
  accountIdentityEnabled: true,
  webAccountSessionEnabled: true,
});

describe("account session token and Cookie primitives", () => {
  it("generates unique 256-bit base64url tokens and deterministic hashes", () => {
    const tokens = Array.from({ length: 128 }, () => generateOpaqueToken());
    expect(new Set(tokens)).toHaveLength(128);
    for (const token of tokens) {
      expect(isValidOpaqueToken(token)).toBe(true);
      expect(Buffer.from(token, "base64url")).toHaveLength(OPAQUE_TOKEN_BYTES);
      expect(hashOpaqueToken(token)).toMatch(/^[0-9a-f]{64}$/);
      expect(hashOpaqueToken(token)).toBe(hashOpaqueToken(token));
      expect(hashOpaqueToken(token)).not.toContain(token);
    }
  });

  it("builds a __Host Cookie with required attributes and reliable deletion", () => {
    const token = generateOpaqueToken();
    const now = new Date("2026-08-06T00:00:00.000Z");
    const expiresAt = new Date("2026-08-07T00:00:00.000Z");
    const cookie = buildWebSessionCookie(token, expiresAt, now);
    expect(cookie).toContain(`${WEB_SESSION_COOKIE_NAME}=${token}`);
    expect(cookie).toContain("HttpOnly");
    expect(cookie).toContain("Secure");
    expect(cookie).toContain("SameSite=Lax");
    expect(cookie).toContain("Path=/");
    expect(cookie).toContain("Max-Age=86400");
    expect(cookie).toContain("Expires=");
    expect(cookie).not.toMatch(/(?:^|;\s*)Domain=/i);
    expect(parseWebSessionCookie(`other=x; ${cookie.split(";", 1)[0]}`)).toBe(
      token,
    );

    const deleted = buildWebSessionDeletionCookie();
    expect(deleted).toContain(`${WEB_SESSION_COOKIE_NAME}=`);
    expect(deleted).toContain("Max-Age=0");
    expect(deleted).toContain("Expires=Thu, 01 Jan 1970 00:00:00 GMT");
    expect(deleted).not.toMatch(/(?:^|;\s*)Domain=/i);
  });

  it("rejects malformed, injected, oversized, and duplicate session Cookies", () => {
    const token = generateOpaqueToken();
    expect(parseWebSessionCookie(null)).toBeNull();
    expect(parseWebSessionCookie(`${WEB_SESSION_COOKIE_NAME}=short`)).toBeNull();
    expect(
      parseWebSessionCookie(
        `${WEB_SESSION_COOKIE_NAME}=${token}; ${WEB_SESSION_COOKIE_NAME}=${token}`,
      ),
    ).toBeNull();
    expect(
      parseWebSessionCookie(`${WEB_SESSION_COOKIE_NAME}=${token}\r\nInjected=x`),
    ).toBeNull();
    expect(parseWebSessionCookie(`x=${"a".repeat(8_200)}`)).toBeNull();
  });
});

describe("account feature and ownership boundaries", () => {
  it("keeps both feature flags false unless the exact value is true", () => {
    expect(accountIdentityFeatureState({})).toEqual({
      accountIdentityEnabled: false,
      webAccountSessionEnabled: false,
    });
    expect(
      isWebSessionIssuanceEnabled(
        accountIdentityFeatureState({
          ACCOUNT_IDENTITY_ENABLED: "TRUE",
          WEB_ACCOUNT_SESSION_ENABLED: "1",
        }),
      ),
    ).toBe(false);
    expect(
      isWebSessionIssuanceEnabled(
        accountIdentityFeatureState({
          ACCOUNT_IDENTITY_ENABLED: "true",
          WEB_ACCOUNT_SESSION_ENABLED: "true",
        }),
      ),
    ).toBe(true);
  });

  it("rejects owner and server-managed field injection recursively", () => {
    expect(() =>
      assertNoClientOwnershipFields({ payload: { ownerId: randomUUID() } }),
    ).toThrowError(expect.objectContaining({ code: "clientOwnershipForbidden" }));
    expect(() =>
      assertNoClientOwnershipFields({ items: [{ clientScope: "abcdef123456" }] }),
    ).toThrowError(expect.objectContaining({ code: "clientOwnershipForbidden" }));
    expect(() =>
      assertNoClientOwnershipFields(
        JSON.parse('{"payload":{"__proto__":{"isAdmin":true}}}'),
      ),
    ).toThrowError(expect.objectContaining({ code: "clientOwnershipForbidden" }));
    expect(() =>
      assertNoClientOwnershipFields({ resourceId: "safe", payload: { count: 1 } }),
    ).not.toThrow();
  });

  it("maps internal failures to a bounded safe error code", () => {
    expect(
      safeAccountSessionErrorCode(new AccountSessionError("sessionExpired")),
    ).toBe("sessionExpired");
    expect(safeAccountSessionErrorCode(new Error("database details"))).toBe(
      "temporarilyUnavailable",
    );
  });
});

describe("Web session service", () => {
  it("does not issue when either feature flag is disabled", async () => {
    const repository = new InMemoryAccountSessionRepository();
    const account = await repository.createAccount();
    const service = createWebSessionService({ repository });
    await expect(
      service.issueSessionForVerifiedAccount(account.id),
    ).rejects.toMatchObject({ code: "featureDisabled" });
    expect(repository.sessions).toHaveLength(0);
  });

  it("does not rotate into a new session while flags are disabled", async () => {
    const fixture = await serviceFixture();
    const issued = await fixture.service.issueSessionForVerifiedAccount(
      fixture.account.id,
    );
    const disabledService = createWebSessionService({
      repository: fixture.repository,
      featureState: () => ({
        accountIdentityEnabled: false,
        webAccountSessionEnabled: false,
      }),
    });
    await expect(
      disabledService.rotateSession(issued.rawToken),
    ).rejects.toMatchObject({ code: "featureDisabled" });
    await expect(fixture.service.resolveSession(issued.rawToken)).resolves.toBeTruthy();
    expect(fixture.repository.sessions).toHaveLength(1);
  });

  it("stores only a hash, sanitizes metadata, and returns raw token once", async () => {
    const fixture = await serviceFixture();
    const issued = await fixture.service.issueSessionForVerifiedAccount(
      fixture.account.id,
      { deviceLabel: "  Home\r\nBrowser  ", platform: "browser-detail" },
    );
    expect(issued.rawToken).toHaveLength(43);
    expect(fixture.repository.sessions).toHaveLength(1);
    const stored = fixture.repository.sessions[0]!;
    expect(stored.tokenHash).toBe(hashOpaqueToken(issued.rawToken));
    expect(stored.deviceLabel).toBe("Home Browser");
    expect(stored.platform).toBe("unknown");
    expect(JSON.stringify(stored)).not.toContain(issued.rawToken);
    expect(JSON.stringify(fixture.audit.events)).not.toContain(issued.rawToken);
  });

  it("resolves active sessions, throttles lastSeen writes, and leaves no raw token in AuthContext", async () => {
    const fixture = await serviceFixture();
    const issued = await fixture.service.issueSessionForVerifiedAccount(
      fixture.account.id,
    );
    const resolved = await fixture.service.resolveSession(issued.rawToken);
    expect(resolved).toMatchObject({
      accountId: fixture.account.id,
      sessionId: issued.sessionId,
      authenticationLevel: "session",
    });
    expect(fixture.repository.touchCount).toBe(0);

    fixture.clock.advance(6 * 60 * 1_000);
    await fixture.service.resolveSession(issued.rawToken);
    expect(fixture.repository.touchCount).toBe(1);

    const context = await resolveAuthContext(
      `${WEB_SESSION_COOKIE_NAME}=${issued.rawToken}`,
      fixture.service,
    );
    expect(context.kind).toBe("account");
    expect(JSON.stringify(context)).not.toContain(issued.rawToken);
  });

  it("rejects expired, revoked, and disabled-account sessions", async () => {
    const expired = await serviceFixture();
    const expiredToken = await expired.service.issueSessionForVerifiedAccount(
      expired.account.id,
    );
    expired.repository.sessions[0]!.expiresAt = new Date(
      expired.clock.now().getTime() - 1,
    );
    await expect(
      expired.service.resolveSession(expiredToken.rawToken),
    ).rejects.toMatchObject({ code: "sessionExpired" });

    const revoked = await serviceFixture();
    const revokedToken = await revoked.service.issueSessionForVerifiedAccount(
      revoked.account.id,
    );
    revoked.repository.sessions[0]!.revokedAt = revoked.clock.now();
    await expect(
      revoked.service.resolveSession(revokedToken.rawToken),
    ).rejects.toMatchObject({ code: "sessionRevoked" });

    const disabled = await serviceFixture();
    const disabledToken = await disabled.service.issueSessionForVerifiedAccount(
      disabled.account.id,
    );
    disabled.repository.disableAccount(disabled.account.id, disabled.clock.now());
    await expect(
      disabled.service.resolveSession(disabledToken.rawToken),
    ).rejects.toMatchObject({ code: "accountDisabled" });
  });

  it("rotates atomically, prevents fixation, and rejects the predecessor", async () => {
    const fixture = await serviceFixture();
    const first = await fixture.service.issueSessionForVerifiedAccount(
      fixture.account.id,
    );
    const rotated = await fixture.service.rotateSession(first.rawToken, {
      deviceLabel: "Rotated",
      platform: "web",
    });
    expect(rotated.rawToken).not.toBe(first.rawToken);
    expect(rotated.sessionId).not.toBe(first.sessionId);
    expect(rotated.sessionVersion).toBe(first.sessionVersion + 1);
    await expect(
      fixture.service.resolveSession(first.rawToken),
    ).rejects.toMatchObject({ code: "sessionRevoked" });
    await expect(fixture.service.resolveSession(rotated.rawToken)).resolves.toMatchObject({
      sessionId: rotated.sessionId,
    });
  });

  it("revokes one session and all account sessions without crossing accounts", async () => {
    const fixture = await serviceFixture();
    const first = await fixture.service.issueSessionForVerifiedAccount(
      fixture.account.id,
    );
    const second = await fixture.service.issueSessionForVerifiedAccount(
      fixture.account.id,
    );
    expect(await fixture.service.revokeSession(first)).toBe(1);
    await expect(fixture.service.resolveSession(first.rawToken)).rejects.toMatchObject({
      code: "sessionRevoked",
    });
    await expect(fixture.service.resolveSession(second.rawToken)).resolves.toBeTruthy();

    expect(await fixture.service.revokeAllAccountSessions(second)).toBe(1);
    await expect(fixture.service.resolveSession(second.rawToken)).rejects.toMatchObject({
      code: "sessionRevoked",
    });
  });

  it("keeps canary tokens out of logs, stored rows, audit, and errors", async () => {
    const repository = new InMemoryAccountSessionRepository();
    const account = await repository.createAccount();
    const audit = new CapturingAuditSink();
    const canary = "A".repeat(43);
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    const service = createWebSessionService({
      repository,
      audit,
      featureState: ENABLED,
      tokenFactory: () => canary,
    });
    const issued = await service.issueSessionForVerifiedAccount(account.id);
    await service.resolveSession(issued.rawToken);
    expect(consoleError).not.toHaveBeenCalled();
    expect(JSON.stringify(repository.sessions)).not.toContain(canary);
    expect(JSON.stringify(audit.events)).not.toContain(canary);
    consoleError.mockRestore();
  });

  it("returns legacyAnonymous without exposing gb_user_id", async () => {
    const legacyId = randomUUID();
    const context = await resolveAuthContext(
      `gb_user_id=${legacyId}; ownerId=${randomUUID()}`,
      noSessionService(),
    );
    expect(context).toEqual({ kind: "legacyAnonymous" });
    expect(JSON.stringify(context)).not.toContain(legacyId);
  });
});

describe("finite database retry", () => {
  it("retries only bounded serialization conflicts", async () => {
    let attempts = 0;
    await expect(
      withFiniteDbRetry(async () => {
        attempts++;
        if (attempts < 3) throw { code: "P2034" };
        return "ok";
      }),
    ).resolves.toBe("ok");
    expect(attempts).toBe(3);

    await expect(
      withFiniteDbRetry(async () => {
        throw { code: "P2034" };
      }, 2),
    ).rejects.toMatchObject({ code: "retryExhausted", retryable: true });
  });
});

class CapturingAuditSink implements AuthAuditSink {
  readonly events: AuthAuditEvent[] = [];

  async record(event: AuthAuditEvent): Promise<void> {
    this.events.push(event);
  }
}

class TestClock {
  constructor(private value = new Date("2026-08-06T00:00:00.000Z")) {}

  now = (): Date => new Date(this.value);

  advance(milliseconds: number): void {
    this.value = new Date(this.value.getTime() + milliseconds);
  }
}

async function serviceFixture() {
  const repository = new InMemoryAccountSessionRepository();
  const account = await repository.createAccount();
  const audit = new CapturingAuditSink();
  const clock = new TestClock();
  const service = createWebSessionService({
    repository,
    audit,
    now: clock.now,
    featureState: ENABLED,
  });
  return { repository, account, audit, clock, service };
}

function noSessionService(): WebSessionService {
  const rejected = async () => {
    throw new AccountSessionError("invalidSession");
  };
  return {
    issueSessionForVerifiedAccount: rejected,
    resolveSession: rejected,
    rotateSession: rejected,
    revokeSession: rejected,
    revokeAllAccountSessions: rejected,
    listSessionMetadata: async () => [],
    cleanupExpiredSessions: async () => 0,
  } as WebSessionService;
}

class InMemoryAccountSessionRepository implements AccountSessionRepository {
  readonly accounts = new Map<string, Account>();
  readonly sessions: WebSession[] = [];
  touchCount = 0;

  async transaction<T>(
    operation: (repository: AccountSessionRepository) => Promise<T>,
  ): Promise<T> {
    return operation(this);
  }

  async createAccount(): Promise<Account> {
    const now = new Date("2026-08-06T00:00:00.000Z");
    const account: Account = {
      id: randomUUID(),
      status: "active",
      version: 1,
      createdAt: now,
      updatedAt: now,
      disabledAt: null,
      deletionRequestedAt: null,
    };
    this.accounts.set(account.id, account);
    return account;
  }

  async findActiveAccount(accountId: string): Promise<Account | null> {
    const account = this.accounts.get(accountId);
    return account?.status === "active" &&
      account.disabledAt === null &&
      account.deletionRequestedAt === null
      ? account
      : null;
  }

  async createSession(input: CreateWebSessionRecordInput): Promise<WebSession> {
    const account = await this.findActiveAccount(input.accountId);
    if (!account) throw new AccountSessionError("accountDisabled");
    if (this.sessions.some((row) => row.tokenHash === input.tokenHash)) {
      throw { code: "P2002" };
    }
    const row = rowFrom(input, account.version);
    this.sessions.push(row);
    return row;
  }

  async resolveSessionByTokenHash(
    tokenHash: string,
  ): Promise<WebSessionWithAccount | null> {
    const session = this.sessions.find((row) => row.tokenHash === tokenHash);
    if (!session) return null;
    const account = this.accounts.get(session.accountId);
    return account ? { ...session, account } : null;
  }

  async rotateSession(
    input: RotateWebSessionRecordInput,
  ): Promise<WebSessionWithAccount> {
    const current = await this.resolveSessionByTokenHash(input.currentTokenHash);
    if (!current) throw new AccountSessionError("invalidSession");
    if (current.revokedAt) throw new AccountSessionError("sessionRevoked");
    if (current.expiresAt <= input.now) {
      throw new AccountSessionError("sessionExpired");
    }
    if (
      current.account.status !== "active" ||
      current.account.disabledAt ||
      current.accountVersion !== current.account.version
    ) {
      throw new AccountSessionError("accountDisabled");
    }
    if (this.sessions.some((row) => row.tokenHash === input.nextTokenHash)) {
      throw { code: "P2002" };
    }
    const replacement: WebSession = {
      ...rowFrom(
        {
          accountId: current.accountId,
          tokenHash: input.nextTokenHash,
          createdAt: input.now,
          expiresAt: current.expiresAt,
          deviceLabel: input.deviceLabel,
          platform: input.platform,
        },
        current.account.version,
      ),
      rotationCounter: current.rotationCounter + 1,
      version: current.version + 1,
    };
    const stored = this.sessions.find((row) => row.id === current.id)!;
    stored.revokedAt = input.now;
    stored.replacedBySessionId = replacement.id;
    stored.version++;
    this.sessions.push(replacement);
    return { ...replacement, account: current.account };
  }

  async revokeSession(
    accountId: string,
    sessionId: string,
    now: Date,
  ): Promise<number> {
    const row = this.sessions.find(
      (candidate) =>
        candidate.id === sessionId &&
        candidate.accountId === accountId &&
        candidate.revokedAt === null,
    );
    if (!row) return 0;
    row.revokedAt = now;
    row.version++;
    return 1;
  }

  async revokeAllSessions(accountId: string, now: Date): Promise<number> {
    const account = await this.findActiveAccount(accountId);
    if (!account) throw new AccountSessionError("accountDisabled");
    account.version++;
    let count = 0;
    for (const row of this.sessions) {
      if (row.accountId === accountId && row.revokedAt === null) {
        row.revokedAt = now;
        row.version++;
        count++;
      }
    }
    return count;
  }

  async touchSessionLastSeen(
    sessionId: string,
    observedLastSeenAt: Date,
    now: Date,
  ): Promise<boolean> {
    const row = this.sessions.find(
      (candidate) =>
        candidate.id === sessionId &&
        candidate.lastSeenAt.getTime() === observedLastSeenAt.getTime() &&
        candidate.revokedAt === null,
    );
    if (!row) return false;
    row.lastSeenAt = now;
    this.touchCount++;
    return true;
  }

  async cleanupExpiredSessions(cutoff: Date, limit = 500): Promise<number> {
    let removed = 0;
    for (let index = this.sessions.length - 1; index >= 0; index--) {
      if (removed >= limit) break;
      if (this.sessions[index]!.expiresAt <= cutoff) {
        this.sessions.splice(index, 1);
        removed++;
      }
    }
    return removed;
  }

  async listSessionMetadata(accountId: string): Promise<SessionMetadataRecord[]> {
    return this.sessions
      .filter((row) => row.accountId === accountId)
      .map((row) => ({
        id: row.id,
        deviceLabel: row.deviceLabel,
        platform: row.platform,
        createdAt: row.createdAt,
        expiresAt: row.expiresAt,
        lastSeenAt: row.lastSeenAt,
        revokedAt: row.revokedAt,
        rotationCounter: row.rotationCounter,
        version: row.version,
      }));
  }

  disableAccount(accountId: string, now: Date): void {
    const account = this.accounts.get(accountId);
    if (!account) return;
    account.status = "locked";
    account.disabledAt = now;
    account.version++;
  }
}

function rowFrom(
  input: CreateWebSessionRecordInput,
  accountVersion: number,
): WebSession {
  return {
    id: randomUUID(),
    accountId: input.accountId,
    tokenHash: input.tokenHash,
    createdAt: input.createdAt,
    expiresAt: input.expiresAt,
    lastSeenAt: input.createdAt,
    revokedAt: null,
    rotationCounter: 0,
    version: 1,
    accountVersion,
    deviceLabel: input.deviceLabel,
    platform: input.platform,
    replacedBySessionId: null,
  };
}
