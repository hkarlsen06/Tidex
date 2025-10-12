import { createSupabaseServerClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import { BackButton } from '@appui/BackButton';
import { getUserSubscriptionData } from './_data/getSubscription';
import { SubscriptionStatus } from '@/components/settings/subscription/SubscriptionStatus';
import { EarlySupporterStatus } from '@/components/settings/subscription/EarlySupporterStatus';
import { GrandfatheredSubscriberBanner } from '@/components/settings/subscription/GrandfatheredSubscriberBanner';
import { FreePlanInfo } from '@/components/settings/subscription/FreePlanInfo';
import { UpgradeOptions } from '@/components/settings/subscription/UpgradeOptions';

export default async function SubscriptionPage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

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
      <BackButton fallbackHref="/settings" />

      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-bold">Abonnement</h2>
          <p className="text-text-secondary mt-1">
            Administrer ditt abonnement og fakturering
          </p>
        </div>

        {isGrandfatheredSubscriber ? (
          <>
            <GrandfatheredSubscriberBanner />
            <SubscriptionStatus subscription={subscription!} isGrandfathered={true} />
          </>
        ) : hasActiveSubscription ? (
          <SubscriptionStatus subscription={subscription!} isGrandfathered={false} />
        ) : subscription ? (
          <>
            {/* Show canceled/expired subscription status */}
            <SubscriptionStatus subscription={subscription} isGrandfathered={false} />
            <UpgradeOptions />
          </>
        ) : isEarlySupporter ? (
          <>
            <EarlySupporterStatus />
            <UpgradeOptions />
          </>
        ) : (
          <>
            <FreePlanInfo />
            <UpgradeOptions />
          </>
        )}
      </div>
    </div>
  );
}
