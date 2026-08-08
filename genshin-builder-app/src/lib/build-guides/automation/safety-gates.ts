import "server-only";

import {
  assertAutomationMayProceed,
  readYoutubeAutomationControl,
} from "./automation-control";
import { youtubeAutomationFlags } from "./feature-flags";
import { isVisualAutoPublishEnabled } from "../visual-auto-publish-settings";

/**
 * Global AI Emergency Stop gate (DB: GuideAutomationControl.emergencyStopped).
 * Same control is enforced again at DeepSeek/Gemini final HTTP call sites via
 * `assertGlobalAiEmergencyAllowsExternalCall`.
 */
export async function assertEmergencyStopAllowsWork(): Promise<void> {
  const control = await readYoutubeAutomationControl();
  assertAutomationMayProceed(control);
}

export type VisualAutoPublishGate =
  | { allowed: true }
  | { allowed: false; reason: string };

/**
 * Visual auto-approve/publish must honor (Production normal = all true + Emergency OFF):
 * 1. BUILD_GUIDE_VISUAL_AUTO_PUBLISH (visual-specific switch; normal ops = "true")
 * 2. GuideAutomationControl.emergencyStopped (Global AI Emergency; ON blocks publish)
 * 3. youtubeAutomationFlags().enabled + autoPublishEnabled (master + publish)
 *
 * Canary paths bypass this by never calling it (skipAutoPublish=true).
 * Manual admin publish uses `evaluateManualPublishGate` (break-glass override).
 * Auto-publish must never pass an override reason.
 */
export async function evaluateVisualAutoPublishGate(
  env: Readonly<Record<string, string | undefined>> = process.env,
): Promise<VisualAutoPublishGate> {
  if (!isVisualAutoPublishEnabled(env)) {
    return { allowed: false, reason: "VISUAL_AUTO_PUBLISH_DISABLED" };
  }
  const control = await readYoutubeAutomationControl();
  if (control.emergencyStopped) {
    return { allowed: false, reason: "EMERGENCY_STOPPED" };
  }
  const flags = youtubeAutomationFlags(env);
  if (!flags.enabled) {
    return { allowed: false, reason: "AUTOMATION_DISABLED" };
  }
  if (!flags.autoPublishEnabled) {
    return { allowed: false, reason: "AUTO_PUBLISH_DISABLED" };
  }
  return { allowed: true };
}
