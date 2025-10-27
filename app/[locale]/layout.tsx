/**
 * Locale Layout
 *
 * Wraps all localized routes and provides i18n context
 * Params include the dynamic [locale] segment
 */

import type { ReactNode } from "react";
import { Suspense } from "react";
import { notFound } from "next/navigation";
import { I18nProvider } from "@/components/providers/I18nProvider";
import { locales, type Locale } from "@/lib/i18n/config";
import { getDictionary } from "@/lib/i18n/dictionaries";

interface LocaleLayoutProps {
  children: ReactNode;
  params: Promise<{ locale: string }>;
}

export async function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export default async function LocaleLayout({ children, params }: LocaleLayoutProps) {
  const { locale } = await params;

  // Validate locale
  if (!locales.includes(locale as Locale)) {
    notFound();
  }

  const dictionary = getDictionary(locale as Locale);

  return (
    <Suspense fallback={null}>
      <I18nProvider locale={locale as Locale} dictionary={dictionary}>
        {children}
      </I18nProvider>
    </Suspense>
  );
}
