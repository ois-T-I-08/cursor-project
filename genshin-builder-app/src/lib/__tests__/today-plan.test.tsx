import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import TodayPlan from "@/components/consumer/TodayPlan";
import { buildDailyPlanDisplayModel } from "@/lib/daily-plan/presentation";
import { parseDailyPlanProposal } from "@/lib/daily-plan/validation";
import type { DailyPlanProposal } from "@/lib/daily-plan/types";

const FIXTURE_PATH = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../../../shared/domain-golden/daily-plan-proposal-v1.json",
);

const LABELS = [
  { taskId: "wd_freedom", title: "自由の導き素材を集める" },
  { taskId: "goal_level", title: "登録済みキャラクターのレベル目標を確認する" },
  { taskId: "goal_talent_locked", title: "天賦素材の開放日を待つ" },
  { taskId: "weapon_goal", title: "武器の育成素材を確認する" },
  { taskId: "boss_goal", title: "週ボスの進み具合を確認する" },
  { taskId: "material_goal", title: "不足している一般素材を確認する" },
];

function fixture(): DailyPlanProposal {
  return parseDailyPlanProposal(JSON.parse(readFileSync(FIXTURE_PATH, "utf8")) as unknown);
}

describe("Today read-only proposal", () => {
  it("shows one primary task, at most two secondary tasks, and keeps reasons collapsed", () => {
    const proposal = fixture();
    const html = renderToStaticMarkup(<TodayPlan proposal={proposal} taskLabels={LABELS} />);
    expect(html.match(/最優先/g)).toHaveLength(1);
    expect(html.match(/次にやること/g)).toHaveLength(1);
    expect(html).toContain("<details");
    expect(html).not.toContain("<details open");
  });

  it("collapses recommendations after the first three", () => {
    const base = fixture();
    const proposal = parseDailyPlanProposal({
      ...base,
      recommendations: [
        ...base.recommendations,
        { taskId: "weapon_goal", priority: 3, category: "do_today", reason: "目標に近いため", suggestedMinutes: 15 },
        { taskId: "boss_goal", priority: 4, category: "do_today", reason: "今週分を確認するため", suggestedMinutes: 20 },
        { taskId: "material_goal", priority: 5, category: "do_today", reason: "不足があるため", suggestedMinutes: 10 },
      ],
    });
    const model = buildDailyPlanDisplayModel(proposal, LABELS);
    expect(model?.primaryTask.title).toBe(LABELS[0].title);
    expect(model?.secondaryTasks).toHaveLength(2);
    expect(model?.remainingTasks).toHaveLength(2);
    const html = renderToStaticMarkup(<TodayPlan proposal={proposal} taskLabels={LABELS} />);
    expect(html).toContain("残りの提案 2件");
  });

  it("uses natural fallback wording and hides internal identifiers", () => {
    const proposal = { ...fixture(), source: "deterministic_fallback" as const };
    const html = renderToStaticMarkup(<TodayPlan proposal={proposal} taskLabels={LABELS} />);
    expect(html).toContain("通常ルールによる提案");
    expect(html).not.toContain("wd_freedom");
    expect(html).not.toContain(proposal.proposalFingerprint);
    expect(html).not.toContain(proposal.inputHash);
    expect(html).not.toContain("do_today");
  });

  it("renders an empty state without inventing a proposal", () => {
    const html = renderToStaticMarkup(<TodayPlan proposal={null} />);
    expect(html).toContain("今日の提案はまだありません");
    expect(html).toContain("閲覧のみ");
  });

  it("fails safely when a task title cannot be resolved", () => {
    const html = renderToStaticMarkup(<TodayPlan proposal={fixture()} taskLabels={[]} />);
    expect(html).toContain("今日の提案を確認できませんでした");
    expect(html).not.toContain("wd_freedom");
  });

  it("wraps long Japanese task text without exposing internal fields", () => {
    const longTitle = "とても長い日本語の育成目標".repeat(12);
    const html = renderToStaticMarkup(
      <TodayPlan
        proposal={fixture()}
        taskLabels={LABELS.map((label, index) => index === 0 ? { ...label, title: longTitle } : label)}
      />,
    );
    expect(html).toContain(longTitle);
    expect(html).toContain("break-words");
  });
});
