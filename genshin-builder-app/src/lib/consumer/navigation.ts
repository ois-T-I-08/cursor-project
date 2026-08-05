export const CONSUMER_NAV_ITEMS = [
  { href: "/today", label: "今日", icon: "today" },
  { href: "/characters", label: "キャラ", icon: "characters" },
  { href: "/growth", label: "育成", icon: "growth" },
  { href: "/teams", label: "編成", icon: "teams" },
  { href: "/more", label: "その他", icon: "more" },
] as const;

export type ConsumerNavIcon = (typeof CONSUMER_NAV_ITEMS)[number]["icon"];

export function isConsumerRouteActive(pathname: string, href: string): boolean {
  return pathname === href || pathname.startsWith(`${href}/`);
}
