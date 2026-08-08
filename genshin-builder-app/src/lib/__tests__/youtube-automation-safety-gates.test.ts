import { beforeEach, describe, expect, it, vi } from "vitest";

const { readControlMock } = vi.hoisted(() => ({
  readControlMock: vi.fn(),
}));

vi.mock("@/lib/build-guides/automation/automation-control", () => ({
  readYoutubeAutomationControl: readControlMock,
  assertAutomationMayProceed: (control: { emergencyStopped: boolean }) => {
    if (control.emergencyStopped) throw new Error("EMERGENCY_STOPPED");
  },
}));

import {
  assertEmergencyStopAllowsWork,
  evaluateVisualAutoPublishGate,
} from "@/lib/build-guides/automation/safety-gates";

describe("Safety Switch gates", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    readControlMock.mockResolvedValue({
      emergencyStopped: false,
      reason: "",
      version: 3,
    });
  });

  it("assertEmergencyStopAllowsWork rejects when emergencyStopped", async () => {
    readControlMock.mockResolvedValue({
      emergencyStopped: true,
      reason: "admin emergency stop",
      version: 4,
    });
    await expect(assertEmergencyStopAllowsWork()).rejects.toThrow(
      "EMERGENCY_STOPPED",
    );
  });

  it("evaluateVisualAutoPublishGate requires visual env + master + autoPublish", async () => {
    const deniedVisual = await evaluateVisualAutoPublishGate({
      BUILD_GUIDE_VISUAL_AUTO_PUBLISH: "false",
      YOUTUBE_AUTOMATION_ENABLED: "true",
      YOUTUBE_GUIDE_ENABLED: "true",
      YOUTUBE_AUTO_PUBLISH_ENABLED: "true",
    });
    expect(deniedVisual).toEqual({
      allowed: false,
      reason: "VISUAL_AUTO_PUBLISH_DISABLED",
    });

    const deniedMaster = await evaluateVisualAutoPublishGate({
      BUILD_GUIDE_VISUAL_AUTO_PUBLISH: "true",
      YOUTUBE_AUTOMATION_ENABLED: "false",
      YOUTUBE_GUIDE_ENABLED: "true",
      YOUTUBE_AUTO_PUBLISH_ENABLED: "true",
    });
    expect(deniedMaster).toEqual({
      allowed: false,
      reason: "AUTOMATION_DISABLED",
    });

    const deniedPublish = await evaluateVisualAutoPublishGate({
      BUILD_GUIDE_VISUAL_AUTO_PUBLISH: "true",
      YOUTUBE_AUTOMATION_ENABLED: "true",
      YOUTUBE_GUIDE_ENABLED: "true",
      YOUTUBE_AUTO_PUBLISH_ENABLED: "false",
    });
    expect(deniedPublish).toEqual({
      allowed: false,
      reason: "AUTO_PUBLISH_DISABLED",
    });
  });

  it("evaluateVisualAutoPublishGate blocks on emergency stop even when all envs true", async () => {
    readControlMock.mockResolvedValue({
      emergencyStopped: true,
      reason: "admin emergency stop",
      version: 9,
    });
    const gate = await evaluateVisualAutoPublishGate({
      BUILD_GUIDE_VISUAL_AUTO_PUBLISH: "true",
      YOUTUBE_AUTOMATION_ENABLED: "true",
      YOUTUBE_GUIDE_ENABLED: "true",
      YOUTUBE_AUTO_PUBLISH_ENABLED: "true",
    });
    expect(gate).toEqual({ allowed: false, reason: "EMERGENCY_STOPPED" });
  });

  it("evaluateVisualAutoPublishGate allows only when all safety conditions hold", async () => {
    const gate = await evaluateVisualAutoPublishGate({
      BUILD_GUIDE_VISUAL_AUTO_PUBLISH: "true",
      YOUTUBE_AUTOMATION_ENABLED: "true",
      YOUTUBE_GUIDE_ENABLED: "true",
      YOUTUBE_AUTO_PUBLISH_ENABLED: "true",
    });
    expect(gate).toEqual({ allowed: true });
  });
});
