import Link from "next/link";

export type ConsumerState = "loading" | "empty" | "error" | "unavailable";

const STATE_LABELS: Record<ConsumerState, string> = {
  loading: "読み込み中",
  empty: "データなし",
  error: "読み込みエラー",
  unavailable: "現在利用できません",
};

export default function ConsumerStatePanel({
  state,
  title,
  description,
  action,
}: {
  state: ConsumerState;
  title: string;
  description: string;
  action?: { href: string; label: string };
}) {
  return (
    <section
      className="consumer-card min-w-0 p-5 sm:p-6"
      role={state === "error" ? "alert" : state === "loading" ? "status" : undefined}
      aria-live={state === "loading" ? "polite" : undefined}
    >
      <p className="text-xs font-bold tracking-wide text-accent">
        {STATE_LABELS[state]}
      </p>
      <h2 className="mt-2 break-words text-lg font-bold">{title}</h2>
      <p className="consumer-muted mt-2 break-words text-sm leading-7">
        {description}
      </p>
      {action ? (
        <Link href={action.href} className="consumer-button mt-5 inline-flex">
          {action.label}
        </Link>
      ) : null}
    </section>
  );
}
