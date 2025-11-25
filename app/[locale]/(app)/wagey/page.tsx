/**
 * Wagey Chat Page
 *
 * AI assistant for managing shifts.
 * Access controlled by subscription tier:
 * - Grandfathered users: Unlimited access
 * - Max subscribers: 20 messages/month
 * - Pro subscribers: 10 messages/month
 * - Free users: See marketing showcase
 */

import { connection } from "next/server";
import { verifySession } from "@/data-access/auth";
import { getWageyAccess } from "@/data-access/wagey";
import { getDictionary } from "@/lib/i18n/dictionaries";
import { I18nProvider } from "@/components/providers/I18nProvider";
import { WageyInterface } from "./_components/WageyInterface";
import { WageyShowcase } from "./_components/WageyShowcase";
import type { Locale } from "@/lib/i18n/config";

type WageyPageProps = {
  params: Promise<{ locale: Locale }>;
};

export default async function WageyPage({ params }: WageyPageProps) {
  await connection(); // Opt out of prerendering

  const { locale } = await params;
  const { user } = await verifySession();
  const dictionary = await getDictionary(locale);

  // Check Wagey access based on subscription
  const wageyAccess = await getWageyAccess();

  // Free users see the marketing showcase
  if (!wageyAccess.hasAccess) {
    return (
      <div className="fixed inset-0 top-(--header-height,4rem) bottom-0 md:static md:inset-auto overflow-y-auto">
        <I18nProvider locale={locale} dictionary={dictionary}>
          <WageyShowcase />
        </I18nProvider>
      </div>
    );
  }

  // Paid/grandfathered users see the chat interface
  return (
    <div className="fixed inset-0 top-(--header-height,4rem) bottom-0 md:static md:inset-auto">
      <I18nProvider locale={locale} dictionary={dictionary}>
        <WageyInterface
          userId={user.id}
          userName={user.user_metadata?.full_name}
          wageyAccess={wageyAccess}
        />
      </I18nProvider>
    </div>
  );
}
