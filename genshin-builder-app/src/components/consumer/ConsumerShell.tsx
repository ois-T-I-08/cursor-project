import type { ReactNode } from "react";
import BookmarkProvider from "@/components/providers/BookmarkProvider";
import ConsumerNavigation from "./ConsumerNavigation";

export default function ConsumerShell({ children }: { children: ReactNode }) {
  return (
    <BookmarkProvider>
      <div className="consumer-shell min-h-dvh">
        <a className="skip-link" href="#consumer-main">
          本文へ移動
        </a>
        <ConsumerNavigation />
        <div className="consumer-content-frame">
          <header className="consumer-mobile-header">
            <span aria-hidden="true" className="text-accent">
              ✦
            </span>
            <span className="font-bold">Genshin Builder</span>
          </header>
          <main id="consumer-main" className="consumer-main" tabIndex={-1}>
            {children}
          </main>
        </div>
      </div>
    </BookmarkProvider>
  );
}
