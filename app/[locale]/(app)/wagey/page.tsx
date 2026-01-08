/**
 * Wagey Chat Page
 *
 * AI assistant for managing shifts.
 * Access controlled by subscription tier:
 * - Grandfathered users: 40-100 messages/month
 * - Max subscribers: 90 messages/month
 * - Pro subscribers: 30 messages/month
 * - Free users: See marketing showcase with option to try 3 messages
 */

import { connection } from "next/server";
import { verifySession } from "@/data-access/auth";
import { getWageyAccess } from "@/data-access/wagey";
import { getDictionary } from "@/lib/i18n/dictionaries";
import { sanitizeDisplayName } from "@/lib/sanitize";
import { I18nProvider } from "@/components/providers/I18nProvider";
import { WageyInterface } from "./_components/WageyInterface";
import { WageyTrialWrapper } from "./_components/WageyTrialWrapper";
import type { Locale } from "@/lib/i18n/config";

type WageyPageProps = {
  params: Promise<{ locale: Locale }>;
};

export default async function WageyPage({ params }: WageyPageProps) {
  await connection(); // Opt out of prerendering

  const { locale } = await params;
  const { user } = await verifySession();
  const dictionary = await getDictionary(locale);

  // Use user's chosen name (full_name) if set, otherwise fall back to OAuth name
  // If neither available, pass undefined - MessageList will use localized "You"/"Deg"
  const rawUserName =
    (user.user_metadata?.full_name as string | undefined);
  const userName = rawUserName ? sanitizeDisplayName(rawUserName) : undefined;

  // Check Wagey access based on subscription
  const wageyAccess = await getWageyAccess();

  // Free users see the showcase with option to try Wagey
  if (!wageyAccess.hasAccess) {
    return (
      <div className="fixed inset-0 top-[calc(4rem+env(safe-area-inset-top))] bottom-0 md:static md:inset-auto md:top-0 overflow-y-auto">
        <I18nProvider locale={locale} dictionary={dictionary}>
          <WageyTrialWrapper
            userId={user.id}
            userName={userName}
            wageyAccess={wageyAccess}
          />
        </I18nProvider>
      </div>
    );
  }

  // Paid/grandfathered users see the chat interface
  return (
    <div className="fixed inset-0 top-[calc(4rem+env(safe-area-inset-top))] bottom-0 md:static md:inset-auto md:top-0">
      <I18nProvider locale={locale} dictionary={dictionary}>
        <WageyInterface
          userId={user.id}
          userName={userName}
          wageyAccess={wageyAccess}
        />
      </I18nProvider>
    </div>
  );
}
