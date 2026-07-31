import "server-only";

import { Prisma, type PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/db";

export const YOUTUBE_AUTOMATION_CONTROL_ID = "youtube-guide";

export type LockedAutomationControl = Readonly<{
  emergencyStopped: boolean;
  reason: string;
  version: number;
}>;

type ControlReader = Pick<PrismaClient, "guideAutomationControl">;

/**
 * Missing or unreadable control state is stopped. Automatic work must never
 * infer permission from an absent singleton row.
 */
export async function readYoutubeAutomationControl(
  client: ControlReader = prisma,
): Promise<LockedAutomationControl> {
  try {
    const control = await client.guideAutomationControl.findUnique({
      where: { id: YOUTUBE_AUTOMATION_CONTROL_ID },
      select: { emergencyStopped: true, reason: true, version: true },
    });
    return (
      control ?? {
        emergencyStopped: true,
        reason: "CONTROL_ROW_MISSING",
        version: -1,
      }
    );
  } catch {
    return {
      emergencyStopped: true,
      reason: "CONTROL_READ_FAILED",
      version: -1,
    };
  }
}

export async function lockYoutubeAutomationControl(
  transaction: Prisma.TransactionClient,
): Promise<LockedAutomationControl> {
  const rows = await transaction.$queryRaw<LockedAutomationControl[]>(
    Prisma.sql`
      SELECT
        "emergencyStopped",
        "reason",
        "version"
      FROM "GuideAutomationControl"
      WHERE "id" = ${YOUTUBE_AUTOMATION_CONTROL_ID}
      FOR UPDATE
    `,
  );
  const control = rows[0];
  if (!control) throw new Error("AUTOMATION_CONTROL_MISSING");
  return control;
}

export function assertAutomationMayProceed(
  control: LockedAutomationControl,
): void {
  if (control.emergencyStopped) throw new Error("EMERGENCY_STOPPED");
}
