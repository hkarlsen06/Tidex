import type { Metadata } from 'next';
import { verifySession } from '@/data-access/auth';
import { getUserSubscriptionData } from '@/data-access/subscription';
import { SubscriptionStatus } from '@/components/settings/subscription/SubscriptionStatus';
import { EarlySupporterStatus } from '@/components/settings/subscription/EarlySupporterStatus';
import { GrandfatheredSubscriberBanner } from '@/components/settings/subscription/GrandfatheredSubscriberBanner';
import { FreePlanInfo } from '@/components/settings/subscription/FreePlanInfo';
import { PlatformAwareUpgradeOptions } from '@/components/settings/subscription/PlatformAwareUpgradeOptions';
import { LegalLinks } from '@/components/settings/subscription/LegalLinks';
import { getTranslations } from '@/lib/i18n/server';
import type { Locale } from '@/lib/i18n/config';
import { SettingsPageWrapper } from '@/components/app/SettingsPageWrapper';
import { hasProAccess } from '@/lib/subscription/hasProAccess';

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = getTranslations(locale as Locale, ['pages.settings']);
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
  const t = getTranslations(locale as Locale, ['pages.settings']);

  // Verify authentication and get user
  const { user } = await verifySession();

  const { subscription, profile } = await getUserSubscriptionData(user.id);

  // Check if user is an early supporter (before paywall)
  const isEarlySupporter = profile?.before_paywall === true;

  // Check if user has an active subscription (using unified entitlement check)
  const hasActiveSubscription = hasProAccess(subscription, profile);

  // Grandfathered subscriber: early supporter with an active subscription
  const isGrandfatheredSubscriber = isEarlySupporter && hasActiveSubscription;

  return (
    <SettingsPageWrapper routeKey="settings-subscription">
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">{t.pages.settings.subscription.title}</h2>
          <p className="text-text-secondary mt-1">
            {t.pages.settings.subscription.subtitle}
          </p>
        </div>

        {isGrandfatheredSubscriber && subscription ? (
          <>
            <GrandfatheredSubscriberBanner t={t} />
            <SubscriptionStatus subscription={subscription} isGrandfathered={true} />
          </>
        ) : hasActiveSubscription && subscription ? (
          <SubscriptionStatus subscription={subscription} isGrandfathered={false} />
        ) : subscription ? (
          <>
            {/* Show canceled/expired subscription status */}
            <SubscriptionStatus subscription={subscription} isGrandfathered={false} />
            <PlatformAwareUpgradeOptions t={t} />
          </>
        ) : isEarlySupporter ? (
          <>
            <EarlySupporterStatus t={t} />
            <PlatformAwareUpgradeOptions t={t} />
          </>
        ) : (
          <>
            <FreePlanInfo t={t} />
            <PlatformAwareUpgradeOptions t={t} />
          </>
        )}

        <LegalLinks />
      </div>
    </SettingsPageWrapper>
  );
}
