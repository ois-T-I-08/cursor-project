import type { ReactNode } from "react";

export default function ConsumerPage({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: ReactNode;
}) {
  return (
    <div className="space-y-6">
      <header className="min-w-0">
        <p className="text-sm font-medium text-accent">Genshin Builder</p>
        <h1 className="mt-1 text-2xl font-bold tracking-tight sm:text-3xl">
          {title}
        </h1>
        <p className="consumer-muted mt-2 max-w-3xl text-sm leading-7 sm:text-base">
          {description}
        </p>
      </header>
      {children}
    </div>
  );
}
