import "server-only";

import { Prisma, type PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/db";
import { YOUTUBE_AUTOMATION_POLICY } from "./quality-policy";

type CircuitClient = Pick<PrismaClient, "$executeRaw" | "$queryRaw">;

const DEFAULT_PROBE_TTL_MS = 5 * 60_000;
const MAX_PROBE_TTL_MS = 15 * 60_000;

export type CircuitPermit = Readonly<{
  providerId: string;
  state: "closed" | "half_open";
  stateVersion: number;
  probeOwner: string;
  probeToken: number;
  probeExpiresAt: Date | null;
}>;

export type CircuitPermission =
  | Readonly<{
      allowed: true;
      probe: boolean;
      state: "closed" | "half_open";
      retryAt: null;
      permit: CircuitPermit;
    }>
  | Readonly<{
      allowed: false;
      probe: false;
      state: "open" | "half_open";
      retryAt: Date;
      permit: null;
    }>;

export type CircuitRecordResult = "recorded" | "stale";

type CircuitRow = {
  state: string;
  openUntil: Date | null;
  probeOwner: string;
  probeToken: number;
  probeExpiresAt: Date | null;
  stateVersion: number;
};

/**
 * Allows closed-circuit traffic and grants one expiring, fenced half-open probe.
 * Expired open cooldowns and abandoned probes are both reclaimed by one CAS.
 */
export async function claimProviderCircuitPermission(input: {
  providerId: string;
  probeOwner: string;
  now: Date;
  probeTtlMs?: number;
  client?: CircuitClient;
}): Promise<CircuitPermission> {
  const client = input.client ?? prisma;
  const probeOwner = input.probeOwner.trim();
  if (!probeOwner) throw new Error("providerCircuitProbeOwnerRequired");
  const probeTtlMs = Math.min(
    MAX_PROBE_TTL_MS,
    Math.max(1, Math.trunc(input.probeTtlMs ?? DEFAULT_PROBE_TTL_MS)),
  );
  const probeExpiresAt = new Date(input.now.getTime() + probeTtlMs);

  await client.$executeRaw(Prisma.sql`
    INSERT INTO "GuideProviderCircuit"
      ("providerId", "state", "failureCount", "lastErrorCode",
       "probeOwner", "probeToken", "stateVersion", "updatedAt")
    VALUES (${input.providerId}, 'closed', 0, '', '', 0, 0, ${input.now})
    ON CONFLICT ("providerId") DO NOTHING
  `);

  const claimed = await client.$queryRaw<CircuitRow[]>(Prisma.sql`
    UPDATE "GuideProviderCircuit"
    SET
      "state" = 'half_open',
      "probeOwner" = ${probeOwner},
      "probeToken" = "probeToken" + 1,
      "probeAcquiredAt" = ${input.now},
      "probeExpiresAt" = ${probeExpiresAt},
      "stateVersion" = "stateVersion" + 1,
      "updatedAt" = ${input.now}
    WHERE
      "providerId" = ${input.providerId}
      AND (
        (
          "state" = 'open'
          AND ("openUntil" IS NULL OR "openUntil" <= ${input.now})
        )
        OR (
          "state" = 'half_open'
          AND ("probeExpiresAt" IS NULL OR "probeExpiresAt" <= ${input.now})
        )
      )
    RETURNING
      "state",
      "openUntil",
      "probeOwner",
      "probeToken",
      "probeExpiresAt",
      "stateVersion"
  `);
  if (claimed.length === 1) {
    return {
      allowed: true,
      probe: true,
      state: "half_open",
      retryAt: null,
      permit: permitFromRow(input.providerId, claimed[0], "half_open"),
    };
  }

  const current = await client.$queryRaw<CircuitRow[]>(Prisma.sql`
    SELECT
      "state",
      "openUntil",
      "probeOwner",
      "probeToken",
      "probeExpiresAt",
      "stateVersion"
    FROM "GuideProviderCircuit"
    WHERE "providerId" = ${input.providerId}
  `);
  const row = current[0];
  if (!row) throw new Error("providerCircuitMissingAfterClaim");
  if (row.state === "closed") {
    return {
      allowed: true,
      probe: false,
      state: "closed",
      retryAt: null,
      permit: permitFromRow(input.providerId, row, "closed"),
    };
  }

  const retryAt =
    row.state === "half_open" ? row.probeExpiresAt : row.openUntil;
  return {
    allowed: false,
    probe: false,
    state: row.state === "half_open" ? "half_open" : "open",
    retryAt:
      retryAt && retryAt.getTime() > input.now.getTime()
        ? retryAt
        : probeExpiresAt,
    permit: null,
  };
}

export async function recordProviderSuccess(input: {
  permit: CircuitPermit;
  now: Date;
  client?: CircuitClient;
}): Promise<CircuitRecordResult> {
  const client = input.client ?? prisma;
  const recorded =
    input.permit.state === "half_open"
      ? await client.$queryRaw<Array<{ providerId: string }>>(Prisma.sql`
          UPDATE "GuideProviderCircuit"
          SET
            "state" = 'closed',
            "failureCount" = 0,
            "lastErrorCode" = '',
            "openedAt" = NULL,
            "openUntil" = NULL,
            "probeOwner" = '',
            "probeAcquiredAt" = NULL,
            "probeExpiresAt" = NULL,
            "stateVersion" = "stateVersion" + 1,
            "updatedAt" = ${input.now}
          WHERE
            "providerId" = ${input.permit.providerId}
            AND "state" = 'half_open'
            AND "stateVersion" = ${input.permit.stateVersion}
            AND "probeOwner" = ${input.permit.probeOwner}
            AND "probeToken" = ${input.permit.probeToken}
            AND "probeExpiresAt" > ${input.now}
          RETURNING "providerId"
        `)
      : await client.$queryRaw<Array<{ providerId: string }>>(Prisma.sql`
          UPDATE "GuideProviderCircuit"
          SET
            "failureCount" = 0,
            "lastErrorCode" = '',
            "updatedAt" = ${input.now}
          WHERE
            "providerId" = ${input.permit.providerId}
            AND "state" = 'closed'
            AND "stateVersion" = ${input.permit.stateVersion}
          RETURNING "providerId"
        `);
  return recorded.length === 1 ? "recorded" : "stale";
}

export async function recordProviderFailure(input: {
  permit: CircuitPermit;
  safeErrorCode: string;
  opensCircuit: boolean;
  now: Date;
  threshold?: number;
  openSeconds?: number;
  client?: CircuitClient;
}): Promise<CircuitRecordResult> {
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

  const recorded =
    input.permit.state === "half_open"
      ? await client.$queryRaw<Array<{ providerId: string }>>(Prisma.sql`
          UPDATE "GuideProviderCircuit"
          SET
            "state" = ${input.opensCircuit ? "open" : "closed"},
            "failureCount" =
              ${input.opensCircuit ? Prisma.sql`"failureCount" + 1` : 0},
            "lastErrorCode" = ${input.safeErrorCode},
            "openedAt" = ${input.opensCircuit ? input.now : null},
            "openUntil" = ${input.opensCircuit ? openUntil : null},
            "probeOwner" = '',
            "probeAcquiredAt" = NULL,
            "probeExpiresAt" = NULL,
            "stateVersion" = "stateVersion" + 1,
            "updatedAt" = ${input.now}
          WHERE
            "providerId" = ${input.permit.providerId}
            AND "state" = 'half_open'
            AND "stateVersion" = ${input.permit.stateVersion}
            AND "probeOwner" = ${input.permit.probeOwner}
            AND "probeToken" = ${input.permit.probeToken}
            AND "probeExpiresAt" > ${input.now}
          RETURNING "providerId"
        `)
      : await client.$queryRaw<Array<{ providerId: string }>>(Prisma.sql`
          UPDATE "GuideProviderCircuit"
          SET
            "failureCount" = CASE
              WHEN ${input.opensCircuit} THEN "failureCount" + 1
              ELSE "failureCount"
            END,
            "lastErrorCode" = ${input.safeErrorCode},
            "state" = CASE
              WHEN ${input.opensCircuit}
                AND "failureCount" + 1 >= ${threshold}
              THEN 'open'
              ELSE 'closed'
            END,
            "openedAt" = CASE
              WHEN ${input.opensCircuit}
                AND "failureCount" + 1 >= ${threshold}
              THEN ${input.now}
              ELSE "openedAt"
            END,
            "openUntil" = CASE
              WHEN ${input.opensCircuit}
                AND "failureCount" + 1 >= ${threshold}
              THEN ${openUntil}
              ELSE "openUntil"
            END,
            "stateVersion" = CASE
              WHEN ${input.opensCircuit}
                AND "failureCount" + 1 >= ${threshold}
              THEN "stateVersion" + 1
              ELSE "stateVersion"
            END,
            "updatedAt" = ${input.now}
          WHERE
            "providerId" = ${input.permit.providerId}
            AND "state" = 'closed'
            AND "stateVersion" = ${input.permit.stateVersion}
          RETURNING "providerId"
        `);
  return recorded.length === 1 ? "recorded" : "stale";
}

function permitFromRow(
  providerId: string,
  row: CircuitRow,
  state: "closed" | "half_open",
): CircuitPermit {
  return {
    providerId,
    state,
    stateVersion: row.stateVersion,
    probeOwner: state === "half_open" ? row.probeOwner : "",
    probeToken: state === "half_open" ? row.probeToken : 0,
    probeExpiresAt: state === "half_open" ? row.probeExpiresAt : null,
  };
}
