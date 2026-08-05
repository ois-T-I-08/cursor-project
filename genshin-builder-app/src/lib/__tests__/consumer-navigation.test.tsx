import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { ConsumerNavigationView } from "@/components/consumer/ConsumerNavigation";
import NotFound from "@/app/not-found";
import { CONSUMER_NAV_ITEMS, isConsumerRouteActive } from "@/lib/consumer/navigation";

const APP_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../app/(consumer)",
);

describe("consumer navigation", () => {
  it("defines the five Flutter-parity destinations", () => {
    expect(CONSUMER_NAV_ITEMS.map(({ href, label }) => ({ href, label }))).toEqual([
      { href: "/today", label: "今日" },
      { href: "/characters", label: "キャラ" },
      { href: "/growth", label: "育成" },
      { href: "/teams", label: "編成" },
      { href: "/more", label: "その他" },
    ]);
  });

  it("renders mobile bottom navigation and desktop sidebar with keyboard links", () => {
    const html = renderToStaticMarkup(<ConsumerNavigationView pathname="/today" />);
    expect(html).toContain("consumer-bottom-nav");
    expect(html).toContain("consumer-sidebar");
    for (const item of CONSUMER_NAV_ITEMS) {
      expect(html.match(new RegExp(`href=\"${item.href}\"`, "g"))).toHaveLength(
        item.href === "/today" ? 3 : 2,
      );
    }
    expect(html).not.toContain('tabindex="-1"');
  });

  it("marks the current destination by text and aria-current", () => {
    const html = renderToStaticMarkup(
      <ConsumerNavigationView pathname="/characters/10000046" />,
    );
    expect(isConsumerRouteActive("/characters/10000046", "/characters")).toBe(true);
    expect(html.match(/aria-current="page"/g)).toHaveLength(2);
    expect(html.match(/（現在のページ）/g)).toHaveLength(2);
  });

  it("keeps every destination directly addressable inside the consumer group", () => {
    for (const item of CONSUMER_NAV_ITEMS) {
      expect(existsSync(path.join(APP_ROOT, item.href.slice(1), "page.tsx"))).toBe(true);
    }
  });

  it("provides a recoverable unknown-route screen", () => {
    const html = renderToStaticMarkup(<NotFound />);
    expect(html).toContain("ページが見つかりません");
    expect(html).toContain('href="/today"');
  });
});
