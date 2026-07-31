import "server-only";

import { Prisma, type PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/db";
import { YOUTUBE_AUTOMATION_POLICY } from "./quality-policy";

type CircuitClient = Pick<
  PrismaClient,
  "$executeRaw" | "$queryRaw" | "guideProviderCircuit"
>;

export type CircuitPermission = Readonly<{
  allowed: boolean;
  probe: boolean;
  state: "closed" | "open" | "half_open";
  retryAt: Date | null;
}>;

/**
 * Allows all closed-circuit traffic, blocks an open circuit, and grants exactly
 * one half-open probe after the cooldown. The UPDATE is a database CAS.
 */
export async function claimProviderCircuitPermission(input: {
  providerId: string;
  now: Date;
  client?: CircuitClient;
}): Promise<CircuitPermission> {
  const client = input.client ?? prisma;
  await client.$executeRaw(Prisma.sql`
    INSERT INTO "GuideProviderCircuit"
      ("providerId", "state", "failureCount", "lastErrorCode", "version", "updatedAt")
    VALUES (${input.providerId}, 'closed', 0, '', 0, ${input.now})
    ON CONFLICT ("providerId") DO NOTHING
  `);
  const probe = await client.$queryRaw<Array<{ providerId: string }>>(Prisma.sql`
    UPDATE "GuideProviderCircuit"
    SET
      "state" = 'half_open',
      "halfOpenProbeAt" = ${input.now},
      "version" = "version" + 1,
      "updatedAt" = ${input.now}
    WHERE
      "providerId" = ${input.providerId}
      AND "state" = 'open'
      AND "openUntil" <= ${input.now}
    RETURNING "providerId"
  `);
  const current = await client.guideProviderCircuit.findUniqueOrThrow({
    where: { providerId: input.providerId },
    select: { state: true, openUntil: true },
  });
  if (probe.length === 1) {
    return { allowed: true, probe: true, state: "half_open", retryAt: null };
  }
  if (current.state === "closed") {
    return { allowed: true, probe: false, state: "closed", retryAt: null };
  }
  return {
    allowed: false,
    probe: false,
    state: current.state === "half_open" ? "half_open" : "open",
    retryAt: current.openUntil,
  };
}

export async function recordProviderSuccess(input: {
  providerId: string;
  now: Date;
  client?: CircuitClient;
}): Promise<void> {
  const client = input.client ?? prisma;
  await client.guideProviderCircuit.upsert({
    where: { providerId: input.providerId },
    create: {
      providerId: input.providerId,
      state: "closed",
      failureCount: 0,
      updatedAt: input.now,
    },
    update: {
      state: "closed",
      failureCount: 0,
      lastErrorCode: "",
      openedAt: null,
      openUntil: null,
      halfOpenProbeAt: null,
      version: { increment: 1 },
      updatedAt: input.now,
    },
  });
}

export async function recordProviderFailure(input: {
  providerId: string;
  safeErrorCode: string;
  opensCircuit: boolean;
  now: Date;
  threshold?: number;
  openSeconds?: number;
  client?: CircuitClient;
}): Promise<void> {
  const client = input.client ?? prisma;
  const threshold = Math.max(
    1,
    input.threshold ?? YOUTUBE_AUTOMATION_POLICY.circuitFailureThreshold,
  );
  const openSeconds = Math.max(
    1,
    input.openSeconds ?? YOUTUBE_AUTOMATION_POLICY.circuitOpenSeconds,
  );
  const openUntil = new Date(input.now.getTime() + openSeconds * 1_000);
  await client.$executeRaw(Prisma.sql`
    INSERT INTO "GuideProviderCircuit"
      ("providerId", "state", "failureCount", "lastErrorCode", "openedAt",
       "openUntil", "halfOpenProbeAt", "version", "updatedAt")
    VALUES (
      ${input.providerId},
      ${input.opensCircuit && threshold <= 1 ? "open" : "closed"},
      1,
      ${input.safeErrorCode},
      ${input.opensCircuit && threshold <= 1 ? input.now : null},
      ${input.opensCircuit && threshold <= 1 ? openUntil : null},
      NULL,
      1,
      ${input.now}
    )
    ON CONFLICT ("providerId") DO UPDATE SET
      "failureCount" = "GuideProviderCircuit"."failureCount" + 1,
      "lastErrorCode" = EXCLUDED."lastErrorCode",
      "state" = CASE
        WHEN ${input.opensCircuit}
          AND (
            "GuideProviderCircuit"."state" = 'half_open'
            OR "GuideProviderCircuit"."failureCount" + 1 >= ${threshold}
          )
        THEN 'open'
        ELSE "GuideProviderCircuit"."state"
      END,
      "openedAt" = CASE
        WHEN ${input.opensCircuit}
          AND (
            "GuideProviderCircuit"."state" = 'half_open'
            OR "GuideProviderCircuit"."failureCount" + 1 >= ${threshold}
          )
        THEN ${input.now}
        ELSE "GuideProviderCircuit"."openedAt"
      END,
      "openUntil" = CASE
        WHEN ${input.opensCircuit}
          AND (
            "GuideProviderCircuit"."state" = 'half_open'
            OR "GuideProviderCircuit"."failureCount" + 1 >= ${threshold}
          )
        THEN ${openUntil}
        ELSE "GuideProviderCircuit"."openUntil"
      END,
      "halfOpenProbeAt" = NULL,
      "version" = "GuideProviderCircuit"."version" + 1,
      "updatedAt" = ${input.now}
  `);
}

