import ConsumerStatePanel from "./ConsumerStatePanel";
import { buildDailyPlanDisplayModel } from "@/lib/daily-plan/presentation";
import type { DailyPlanTaskLabel } from "@/lib/daily-plan/presentation";
import type { DailyPlanProposal } from "@/lib/daily-plan/types";

function TaskCard({
  task,
  prominence = "normal",
}: {
  task: { title: string; reason: string; suggestedMinutes: number };
  prominence?: "primary" | "normal";
}) {
  return (
    <article
      className={`min-w-0 rounded-xl border p-4 ${
        prominence === "primary"
          ? "border-accent bg-accent-soft"
          : "border-app-border bg-surface"
      }`}
    >
      <p className="text-xs font-bold text-accent">
        {prominence === "primary" ? "最優先" : "次にやること"}
      </p>
      <h3 className="mt-1 break-words font-bold">{task.title}</h3>
      <p className="consumer-muted mt-1 text-sm">目安 {task.suggestedMinutes}分</p>
      <details className="mt-3 text-sm">
        <summary className="min-h-11 cursor-pointer py-2 font-medium">
          理由を見る
        </summary>
        <p className="consumer-muted break-words pb-1 leading-6">{task.reason}</p>
      </details>
    </article>
  );
}

export default function TodayPlan({
  proposal,
  taskLabels = [],
}: {
  proposal: DailyPlanProposal | null;
  taskLabels?: DailyPlanTaskLabel[];
}) {
  if (!proposal) {
    return (
      <ConsumerStatePanel
        state="empty"
        title="今日の提案はまだありません"
        description="モバイル版の提案をWebへ安全に引き継ぐ仕組みを準備しています。現在は閲覧のみで、提案の採用や育成データの変更は行いません。"
        action={{ href: "/characters", label: "キャラクターを確認する" }}
      />
    );
  }

  const model = buildDailyPlanDisplayModel(proposal, taskLabels);
  if (!model) {
    return (
      <ConsumerStatePanel
        state="error"
        title="今日の提案を確認できませんでした"
        description="提案とキャラクター情報の対応を確認できません。しばらくしてからもう一度お試しください。"
      />
    );
  }

  return (
    <section className="consumer-card min-w-0 space-y-5 p-5 sm:p-6">
      <header className="min-w-0">
        <p className="text-xs font-bold text-accent">今日の提案</p>
        <h2 className="mt-1 break-words text-xl font-bold">{model.summary}</h2>
        <dl className="consumer-muted mt-3 flex flex-wrap gap-x-5 gap-y-1 text-xs">
          <div className="flex gap-1">
            <dt>提案方法:</dt>
            <dd>{model.sourceLabel}</dd>
          </div>
          <div className="flex gap-1">
            <dt>生成日時:</dt>
            <dd>{model.generatedAtLabel}</dd>
          </div>
        </dl>
      </header>

      <TaskCard task={model.primaryTask} prominence="primary" />

      {model.secondaryTasks.length > 0 ? (
        <div className="grid min-w-0 gap-3 sm:grid-cols-2">
          {model.secondaryTasks.map((task) => (
            <TaskCard key={task.title} task={task} />
          ))}
        </div>
      ) : null}

      {model.remainingTasks.length > 0 ? (
        <details className="rounded-xl border border-app-border bg-surface p-3">
          <summary className="min-h-11 cursor-pointer py-2 font-bold">
            残りの提案 {model.remainingTasks.length}件
          </summary>
          <div className="mt-2 grid min-w-0 gap-3">
            {model.remainingTasks.map((task) => (
              <TaskCard key={task.title} task={task} />
            ))}
          </div>
        </details>
      ) : null}

      {model.deferredTasks.length > 0 ? (
        <details className="rounded-xl border border-app-border bg-surface p-3">
          <summary className="min-h-11 cursor-pointer py-2 font-bold">
            今回は見送った候補 {model.deferredTasks.length}件
          </summary>
          <ul className="consumer-muted mt-2 list-disc space-y-1 pl-5 text-sm">
            {model.deferredTasks.map((title) => (
              <li key={title} className="break-words">{title}</li>
            ))}
          </ul>
        </details>
      ) : null}

      {model.warnings.length > 0 ? (
        <details className="rounded-xl border border-app-border bg-surface p-3">
          <summary className="min-h-11 cursor-pointer py-2 font-bold">
            提案について確認する
          </summary>
          <ul className="consumer-muted mt-2 list-disc space-y-1 pl-5 text-sm">
            {model.warnings.map((warning) => (
              <li key={warning} className="break-words">{warning}</li>
            ))}
          </ul>
        </details>
      ) : null}
    </section>
  );
}
