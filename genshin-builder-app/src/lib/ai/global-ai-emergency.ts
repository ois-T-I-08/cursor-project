import "server-only";

import {
  assertAutomationMayProceed,
  readYoutubeAutomationControl,
  type LockedAutomationControl,
} from "@/lib/build-guides/automation/automation-control";

/**
 * Global AI Emergency Stop.
 *
 * Storage reuses `GuideAutomationControl.emergencyStopped` (id=`youtube-guide`).
 * Semantics (Audit 2A): stops new external AI calls and new auto-publish across
 * YouTube automation, Gemini, DeepSeek (guide / daily-plan / team), discovery,
 * transcript analysis, and retries that would hit providers again.
 *
 * Manual admin publish is blocked unless an explicit break-glass override
 * reason is supplied (does not clear emergencyStopped, does not enable auto-publish).
 */
export async function readGlobalAiEmergencyControl(): Promise<LockedAutomationControl> {
  return readYoutubeAutomationControl();
}

export async function assertGlobalAiEmergencyAllowsExternalCall(): Promise<void> {
  const control = await readYoutubeAutomationControl();
  assertAutomationMayProceed(control);
}

export type ManualPublishGate =
  | { allowed: true; overrideUsed: false }
  | {
      allowed: true;
      overrideUsed: true;
      actor: string;
      reason: string;
      controlVersion: number;
    }
  | { allowed: false; reason: "emergencyStoppedPublishBlocked" };

const MIN_OVERRIDE_REASON_CHARS = 8;

/**
 * Final publish gate. Auto-publish callers must omit override fields so
 * emergency stop always blocks them.
 */
export async function evaluateManualPublishGate(input: {
  overrideReason?: string;
  overrideActor?: string;
} = {}): Promise<ManualPublishGate> {
  const control = await readYoutubeAutomationControl();
  if (!control.emergencyStopped) {
    return { allowed: true, overrideUsed: false };
  }
  const reason = input.overrideReason?.trim() ?? "";
  if (reason.length < MIN_OVERRIDE_REASON_CHARS) {
    return { allowed: false, reason: "emergencyStoppedPublishBlocked" };
  }
  return {
    allowed: true,
    overrideUsed: true,
    actor: (input.overrideActor?.trim() || "admin").slice(0, 128),
    reason: reason.slice(0, 500),
    controlVersion: control.version,
  };
}
