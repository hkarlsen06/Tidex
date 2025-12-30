import { connection } from "next/server";
import { verifyAdmin } from "@/data-access/auth";
import { getTranslations } from "@/lib/i18n/server";
import { SettingsPageWrapper } from "@/components/app/SettingsPageWrapper";
import { AdminDashboard } from "@/components/settings/admin/AdminDashboard";
import type { Locale } from "@/lib/i18n/config";

export default async function AdminPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  await connection(); // Opt out of prerendering
  const { locale } = await params;

  // Server-side guard - redirects non-admins to /settings
  await verifyAdmin();

  const t = getTranslations(locale as Locale, ["pages.settings"]);

  return (
    <SettingsPageWrapper routeKey="settings-admin">
      <AdminDashboard dictionary={t} />
    </SettingsPageWrapper>
  );
}
