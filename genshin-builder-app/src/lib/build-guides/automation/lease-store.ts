import "server-only";

import { Prisma, type PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/db";

type RawClient = Pick<PrismaClient, "$queryRaw" | "$executeRaw">;

export type PipelineLease = {
  lockKey: string;
  leaseOwner: string;
  leaseAcquiredAt: Date;
  leaseExpiresAt: Date;
  leaseVersion: number;
};

export async function acquirePipelineLease(input: {
  lockKey: string;
  leaseOwner: string;
  now: Date;
  ttlMs: number;
  client?: RawClient;
}): Promise<PipelineLease | null> {
  const client = input.client ?? prisma;
  const expiresAt = new Date(input.now.getTime() + Math.max(1_000, input.ttlMs));
  const rows = await client.$queryRaw<PipelineLease[]>(Prisma.sql`
    INSERT INTO "GuidePipelineLease"
      ("lockKey", "leaseOwner", "leaseAcquiredAt", "leaseExpiresAt", "leaseVersion", "updatedAt")
    VALUES
      (${input.lockKey}, ${input.leaseOwner}, ${input.now}, ${expiresAt}, 1, ${input.now})
    ON CONFLICT ("lockKey") DO UPDATE SET
      "leaseOwner" = EXCLUDED."leaseOwner",
      "leaseAcquiredAt" = EXCLUDED."leaseAcquiredAt",
      "leaseExpiresAt" = EXCLUDED."leaseExpiresAt",
      "leaseVersion" = "GuidePipelineLease"."leaseVersion" + 1,
      "updatedAt" = EXCLUDED."updatedAt"
    WHERE "GuidePipelineLease"."leaseExpiresAt" <= ${input.now}
    RETURNING
      "lockKey", "leaseOwner", "leaseAcquiredAt", "leaseExpiresAt", "leaseVersion"
  `);
  return rows[0] ?? null;
}

export async function renewPipelineLease(input: {
  lease: PipelineLease;
  now: Date;
  ttlMs: number;
  client?: RawClient;
}): Promise<PipelineLease | null> {
  const client = input.client ?? prisma;
  const expiresAt = new Date(input.now.getTime() + Math.max(1_000, input.ttlMs));
  const rows = await client.$queryRaw<PipelineLease[]>(Prisma.sql`
    UPDATE "GuidePipelineLease"
    SET
      "leaseExpiresAt" = ${expiresAt},
      "leaseVersion" = "leaseVersion" + 1,
      "updatedAt" = ${input.now}
    WHERE
      "lockKey" = ${input.lease.lockKey}
      AND "leaseOwner" = ${input.lease.leaseOwner}
      AND "leaseVersion" = ${input.lease.leaseVersion}
      AND "leaseExpiresAt" > ${input.now}
    RETURNING
      "lockKey", "leaseOwner", "leaseAcquiredAt", "leaseExpiresAt", "leaseVersion"
  `);
  return rows[0] ?? null;
}

export async function releasePipelineLease(input: {
  lease: PipelineLease;
  client?: RawClient;
}): Promise<boolean> {
  const client = input.client ?? prisma;
  const count = await client.$executeRaw(Prisma.sql`
    UPDATE "GuidePipelineLease"
    SET
      "leaseExpiresAt" = "leaseAcquiredAt",
      "updatedAt" = "leaseAcquiredAt"
    WHERE
      "lockKey" = ${input.lease.lockKey}
      AND "leaseOwner" = ${input.lease.leaseOwner}
      AND "leaseVersion" = ${input.lease.leaseVersion}
      AND "leaseExpiresAt" > "leaseAcquiredAt"
  `);
  return count === 1;
}
