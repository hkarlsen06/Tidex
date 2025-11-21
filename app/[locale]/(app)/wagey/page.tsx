/**
 * Wagey Chat Page
 *
 * AI assistant for managing shifts
 */

import { connection } from "next/server";
import { verifySession } from "@/data-access/auth";
import { getDictionary } from "@/lib/i18n/dictionaries";
import { I18nProvider } from "@/components/providers/I18nProvider";
import { WageyInterface } from "./_components/WageyInterface";
import type { Locale } from "@/lib/i18n/config";

type WageyPageProps = {
  params: Promise<{ locale: Locale }>;
};

export default async function WageyPage({ params }: WageyPageProps) {
  await connection(); // Opt out of prerendering

  const { locale } = await params;
  const { user } = await verifySession();
  const dictionary = await getDictionary(locale);

  return (
    <div className="fixed inset-0 top-(--header-height,4rem) bottom-0 md:static md:inset-auto">
      <I18nProvider locale={locale} dictionary={dictionary}>
        <WageyInterface userId={user.id} userName={user.user_metadata?.full_name} />
      </I18nProvider>
    </div>
  );
}
