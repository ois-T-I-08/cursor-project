import { randomUUID } from "node:crypto";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import { createWebSessionService } from "@/lib/auth/web-session-service";
import { generateOpaqueToken, hashOpaqueToken } from "@/lib/auth/tokens";
import { PrismaAccountSessionRepository } from "@/lib/repository/account-session";

const runDbTests = process.env.RUN_ACCOUNT_SESSION_DB_TEST === "true";
const ENABLED = () => ({
  accountIdentityEnabled: true,
  webAccountSessionEnabled: true,
});

describe.runIf(runDbTests)("account session PostgreSQL integration", () => {
  const repository = new PrismaAccountSessionRepository();
  const service = createWebSessionService({
    repository,
    featureState: ENABLED,
  });

  beforeEach(clearAccountData);

  afterAll(async () => {
    await clearAccountData();
    await prisma.$disconnect();
  });

  it("enforces opaque IDs, identity/hash uniqueness, FKs, and deletion policy", async () => {
    const account = await repository.createAccount();
    expect(account.id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
    expect(account).toMatchObject({ status: "active", version: 1 });

    await prisma.authIdentity.create({
      data: {
        accountId: account.id,
        provider: "fixture",
        providerSubject: "subject-a",
      },
    });
    await expect(
      prisma.authIdentity.create({
        data: {
          accountId: account.id,
          provider: "fixture",
          providerSubject: "subject-a",
        },
      }),
    ).rejects.toMatchObject({ code: "P2002" });

    const tokenHash = hashOpaqueToken(generateOpaqueToken());
    await prisma.webSession.create({
      data: {
        accountId: account.id,
        tokenHash,
        accountVersion: account.version,
        expiresAt: new Date(Date.now() + 60_000),
      },
    });
    await expect(
      prisma.webSession.create({
        data: {
          accountId: account.id,
          tokenHash,
          accountVersion: account.version,
          expiresAt: new Date(Date.now() + 60_000),
        },
      }),
    ).rejects.toMatchObject({ code: "P2002" });
    await expect(
      prisma.webSession.create({
        data: {
          accountId: randomUUID(),
          tokenHash: hashOpaqueToken(generateOpaqueToken()),
          accountVersion: 1,
          expiresAt: new Date(Date.now() + 60_000),
        },
      }),
    ).rejects.toMatchObject({ code: "P2003" });

    await prisma.anonymousIdentity.create({
      data: {
        secretHash: hashOpaqueToken(generateOpaqueToken()),
        expiresAt: new Date(Date.now() + 60_000),
        claimedAt: new Date(),
        claimedAccountId: account.id,
      },
    });
    await prisma.account.delete({ where: { id: account.id } });
    expect(await prisma.authIdentity.count()).toBe(0);
    expect(await prisma.webSession.count()).toBe(0);
    expect(
      await prisma.anonymousIdentity.findFirstOrThrow({
        select: { claimedAccountId: true },
      }),
    ).toEqual({ claimedAccountId: null });
  });

  it("allows only one concurrent rotation winner and rejects the predecessor", async () => {
    const account = await repository.createAccount();
    const issued = await service.issueSessionForVerifiedAccount(account.id);
    const results = await Promise.allSettled([
      service.rotateSession(issued.rawToken),
      service.rotateSession(issued.rawToken),
    ]);
    const winners = results.filter(
      (result): result is PromiseFulfilledResult<Awaited<ReturnType<typeof service.rotateSession>>> =>
        result.status === "fulfilled",
    );
    expect(winners).toHaveLength(1);
    expect(results.filter((result) => result.status === "rejected")).toHaveLength(1);
    await expect(service.resolveSession(issued.rawToken)).rejects.toMatchObject({
      code: "sessionRevoked",
    });
    await expect(
      service.resolveSession(winners[0]!.value.rawToken),
    ).resolves.toMatchObject({ sessionId: winners[0]!.value.sessionId });
    expect(await prisma.webSession.count()).toBe(2);
  });

  it("fences rotate versus revoke-all and disabled-account races", async () => {
    const account = await repository.createAccount();
    const issued = await service.issueSessionForVerifiedAccount(account.id);
    const race = await Promise.allSettled([
      service.rotateSession(issued.rawToken),
      service.revokeAllAccountSessions(issued),
    ]);
    const rotated = race.find(
      (result): result is PromiseFulfilledResult<Awaited<ReturnType<typeof service.rotateSession>>> =>
        result.status === "fulfilled" && typeof result.value !== "number",
    );
    await expect(service.resolveSession(issued.rawToken)).rejects.toBeTruthy();
    if (rotated) {
      await expect(
        service.resolveSession(rotated.value.rawToken),
      ).rejects.toBeTruthy();
    }

    const secondAccount = await repository.createAccount();
    const second = await service.issueSessionForVerifiedAccount(secondAccount.id);
    await Promise.allSettled([
      service.resolveSession(second.rawToken),
      prisma.account.update({
        where: { id: secondAccount.id },
        data: {
          status: "locked",
          disabledAt: new Date(),
          version: { increment: 1 },
        },
      }),
    ]);
    await expect(service.resolveSession(second.rawToken)).rejects.toMatchObject({
      code: "accountDisabled",
    });
    await expect(
      service.issueSessionForVerifiedAccount(secondAccount.id),
    ).rejects.toMatchObject({ code: "accountDisabled" });
  });

  it("rolls back transactions and scopes revoke/list operations to the account", async () => {
    await expect(
      repository.transaction(async (transaction) => {
        await transaction.createAccount();
        throw new Error("rollback-fixture");
      }),
    ).rejects.toThrow("rollback-fixture");
    expect(await prisma.account.count()).toBe(0);

    const accountA = await repository.createAccount();
    const accountB = await repository.createAccount();
    const sessionA = await service.issueSessionForVerifiedAccount(accountA.id, {
      deviceLabel: "A",
    });
    const sessionB = await service.issueSessionForVerifiedAccount(accountB.id, {
      deviceLabel: "B",
    });
    expect(
      await service.revokeSession({
        ...sessionA,
        sessionId: sessionB.sessionId,
      }),
    ).toBe(0);
    await expect(service.resolveSession(sessionB.rawToken)).resolves.toBeTruthy();
    expect(await service.listSessionMetadata(sessionA)).toHaveLength(1);
    expect(await service.listSessionMetadata(sessionB)).toHaveLength(1);

    await prisma.webSession.update({
      where: { id: sessionA.sessionId },
      data: { expiresAt: new Date(Date.now() - 1) },
    });
    expect(await service.cleanupExpiredSessions(new Date())).toBe(1);
    expect(await prisma.webSession.count({ where: { accountId: accountB.id } })).toBe(1);
  });
});

async function clearAccountData(): Promise<void> {
  await prisma.webSession.deleteMany();
  await prisma.authIdentity.deleteMany();
  await prisma.anonymousIdentity.deleteMany();
  await prisma.account.deleteMany();
}
