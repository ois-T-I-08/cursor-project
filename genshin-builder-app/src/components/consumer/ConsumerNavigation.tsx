"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  CONSUMER_NAV_ITEMS,
  isConsumerRouteActive,
  type ConsumerNavIcon,
} from "@/lib/consumer/navigation";

function NavigationIcon({ name }: { name: ConsumerNavIcon }) {
  const paths: Record<ConsumerNavIcon, React.ReactNode> = {
    today: (
      <>
        <path d="M6 3v3M18 3v3M4 9h16" />
        <rect x="4" y="5" width="16" height="15" rx="2" />
        <path d="m9 14 2 2 4-4" />
      </>
    ),
    characters: (
      <>
        <circle cx="12" cy="8" r="4" />
        <path d="M5 21a7 7 0 0 1 14 0" />
      </>
    ),
    growth: (
      <>
        <path d="M12 21V10" />
        <path d="M12 14c-4 0-7-2-7-6 4 0 7 2 7 6Z" />
        <path d="M12 10c4 0 7-2 7-6-4 0-7 2-7 6Z" />
      </>
    ),
    teams: (
      <>
        <circle cx="8" cy="9" r="3" />
        <circle cx="17" cy="8" r="2.5" />
        <path d="M3 20a5 5 0 0 1 10 0M13 19a4 4 0 0 1 8 0" />
      </>
    ),
    more: (
      <>
        <circle cx="5" cy="12" r="1" />
        <circle cx="12" cy="12" r="1" />
        <circle cx="19" cy="12" r="1" />
      </>
    ),
  };

  return (
    <svg
      aria-hidden="true"
      className="h-6 w-6 shrink-0"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {paths[name]}
    </svg>
  );
}

export function ConsumerNavigationView({ pathname }: { pathname: string }) {
  const links = CONSUMER_NAV_ITEMS.map((item) => {
    const active = isConsumerRouteActive(pathname, item.href);
    return (
      <Link
        key={item.href}
        href={item.href}
        aria-current={active ? "page" : undefined}
        className="consumer-nav-link group"
      >
        <NavigationIcon name={item.icon} />
        <span className="consumer-nav-label">{item.label}</span>
        {active ? <span className="sr-only">（現在のページ）</span> : null}
      </Link>
    );
  });

  return (
    <>
      <aside className="consumer-sidebar" aria-label="アプリナビゲーション">
        <Link href="/today" className="consumer-brand focus-ring">
          <span aria-hidden="true">✦</span>
          <span className="consumer-brand-label">Genshin Builder</span>
        </Link>
        <nav className="mt-5 flex flex-1 flex-col gap-2">{links}</nav>
      </aside>

      <nav
        className="consumer-bottom-nav"
        aria-label="アプリナビゲーション"
      >
        {links}
      </nav>
    </>
  );
}

export default function ConsumerNavigation() {
  return <ConsumerNavigationView pathname={usePathname()} />;
}
