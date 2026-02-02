/**
 * Locale Layout
 *
 * Wraps all localized routes and provides i18n context
 * Params include the dynamic [locale] segment
 */

import type { ReactNode } from "react";
import { Suspense } from "react";
import { notFound } from "next/navigation";
import { locales, type Locale } from "@/lib/i18n/config";

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

  return (
    <Suspense fallback={null}>
      {children}
    </Suspense>
  );
}
