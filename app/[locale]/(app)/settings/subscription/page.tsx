import { redirect } from 'next/navigation';
import type { Metadata } from 'next';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { getUserSubscriptionData } from './_data/getSubscription';
import { SubscriptionStatus } from '@/components/settings/subscription/SubscriptionStatus';
import { EarlySupporterStatus } from '@/components/settings/subscription/EarlySupporterStatus';
import { GrandfatheredSubscriberBanner } from '@/components/settings/subscription/GrandfatheredSubscriberBanner';
import { FreePlanInfo } from '@/components/settings/subscription/FreePlanInfo';
import { UpgradeOptions } from '@/components/settings/subscription/UpgradeOptions';
import { getTranslations } from '@/lib/i18n/server';
import type { Locale } from '@/lib/i18n/config';

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = getTranslations(locale as Locale);
  return {
    title: t.pages.settings.subscription.title,
  };
}

export default async function SubscriptionPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = getTranslations(locale as Locale);

  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (!user) {
    redirect('/login');
  }

  const { subscription, profile } = await getUserSubscriptionData(user.id);

  // Check if user is an early supporter (before paywall)
  const isEarlySupporter = profile?.before_paywall === true;

  // Check if user has an active subscription (status must be 'active')
  const hasActiveSubscription = subscription?.status === 'active';

  // Grandfathered subscriber: early supporter with an active subscription
  const isGrandfatheredSubscriber = isEarlySupporter && hasActiveSubscription;

  return (
    <div className="container mx-auto px-4 py-8 max-w-4xl">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.subscription.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.subscription.subtitle}
          </p>
        </div>

        {isGrandfatheredSubscriber ? (
          <>
            <GrandfatheredSubscriberBanner t={t} />
            <SubscriptionStatus subscription={subscription!} isGrandfathered={true} />
          </>
        ) : hasActiveSubscription ? (
          <SubscriptionStatus subscription={subscription!} isGrandfathered={false} />
        ) : subscription ? (
          <>
            {/* Show canceled/expired subscription status */}
            <SubscriptionStatus subscription={subscription} isGrandfathered={false} />
            <UpgradeOptions t={t} />
          </>
        ) : isEarlySupporter ? (
          <>
            <EarlySupporterStatus t={t} />
            <UpgradeOptions t={t} />
          </>
        ) : (
          <>
            <FreePlanInfo t={t} />
            <UpgradeOptions t={t} />
          </>
        )}
      </div>
    </div>
  );
}
