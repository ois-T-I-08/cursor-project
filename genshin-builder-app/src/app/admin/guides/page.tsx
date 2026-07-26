import type { Metadata } from "next";
import GuideAdminWorkbench from "@/components/admin/guides/GuideAdminWorkbench";

export const metadata: Metadata = {
  title: "Build Guide 管理",
  robots: { index: false, follow: false },
};

export const dynamic = "force-dynamic";

export default function AdminGuidesPage() {
  // Client workbench fetches only after the operator supplies Bearer secret.
  // No server-side secret or recommendation payload is embedded in HTML.
  return <GuideAdminWorkbench />;
}
