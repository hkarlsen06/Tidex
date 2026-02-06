import type { ReactNode } from "react";
import type { Metadata } from "next";
import { getTranslations } from "@/lib/i18n/server";
import type { Locale } from "@/lib/i18n/config";
import { SettingsLayoutClient } from "@/components/settings/SettingsLayoutClient";
import { getAppDictionary } from "@/lib/i18n/dictionaries";
import { I18nProvider } from "@/components/providers/I18nProvider";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.settings']);
  return {
    title: t.pages.settings.title,
  };
}

export default async function SettingsLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const dictionary = getAppDictionary(locale as Locale, ['pages.settings', 'pages.shifts']);

  return (
    <I18nProvider locale={locale as Locale} dictionary={dictionary} namespaces={['pages.settings', 'pages.shifts']}>
      <SettingsLayoutClient>{children}</SettingsLayoutClient>
    </I18nProvider>
  );
}
