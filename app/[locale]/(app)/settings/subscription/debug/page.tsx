import { verifySession } from '@/data-access/auth';
import { getUserSubscriptionData } from '@/data-access/subscription';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { hasProAccess, getActiveProvider } from '@/lib/subscription/hasProAccess';
import { Card } from '@/components/app/Card';
import { redirect } from 'next/navigation';
import Link from 'next/link';

// Developer user ID for access control
const DEV_USER_ID = '032d8c2a-9af6-4777-99f0-24e2c4058bf3';

export default async function SubscriptionDebugPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const { user } = await verifySession();

  // Only allow developer access
  if (user.id !== DEV_USER_ID) {
    redirect(`/${locale}/settings/subscription`);
  }

  const { subscription, profile } = await getUserSubscriptionData(user.id);
  const supabase = await createSupabaseServerClient();
  const serviceClient = createSupabaseServiceClient();

  // Get entitlement status from DB function
  const { data: entitlementStatus } = await supabase.rpc('get_user_entitlement_status', {
    p_user_id: user.id,
  });

  // Get app account token (requires service role for internal schema)
  const { data: appAccountToken } = await serviceClient
    .schema('internal').from('app_account_tokens')
    .select('token, created_at')
    .eq('user_id', user.id)
    .maybeSingle();

  // Get recent Apple notifications for this user (requires service role for internal schema)
  const { data: recentNotifications } = subscription?.apple_original_transaction_id
    ? await serviceClient
        .schema('internal').from('apple_notifications')
        .select('*')
        .eq('original_transaction_id', subscription.apple_original_transaction_id)
        .order('received_at', { ascending: false })
        .limit(5)
    : { data: null };

  const isEntitled = hasProAccess(subscription, profile);
  const provider = getActiveProvider(subscription);

  return (
    <div className="space-y-6 max-w-2xl mx-auto p-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Subscription Debug</h1>
        <Link
          href={`/${locale}/settings/subscription`}
          className="text-sm text-text-secondary hover:text-text-primary"
        >
          Back to Subscription
        </Link>
      </div>

      {/* Entitlement Status */}
      <Card className="p-4">
        <h2 className="text-lg font-semibold mb-4">Entitlement Status</h2>
        <div className="space-y-2 text-sm">
          <div className="flex justify-between">
            <span className="text-text-secondary">Is Entitled:</span>
            <span className={isEntitled ? 'text-green-500' : 'text-red-500'}>
              {isEntitled ? 'Yes' : 'No'}
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-text-secondary">Active Provider:</span>
            <span>{provider ?? 'None'}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-text-secondary">Is Grandfathered:</span>
            <span>{profile?.before_paywall ? 'Yes' : 'No'}</span>
          </div>
        </div>
      </Card>

      {/* DB Entitlement Function Result */}
      <Card className="p-4">
        <h2 className="text-lg font-semibold mb-4">DB Entitlement Check</h2>
        <pre className="text-xs bg-surface-secondary p-3 rounded overflow-auto">
          {JSON.stringify(entitlementStatus, null, 2)}
        </pre>
      </Card>

      {/* Subscription Record */}
      <Card className="p-4">
        <h2 className="text-lg font-semibold mb-4">Subscription Record</h2>
        {subscription ? (
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-text-secondary">Provider:</span>
              <span>{subscription.provider}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-text-secondary">Status:</span>
              <span>{subscription.status}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-text-secondary">Product ID:</span>
              <span>{subscription.product_id ?? subscription.price_id ?? 'N/A'}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-text-secondary">Period End:</span>
              <span>
                {subscription.current_period_end
                  ? new Date(subscription.current_period_end).toLocaleString()
                  : 'N/A'}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-text-secondary">Cancel at Period End:</span>
              <span>{subscription.cancel_at_period_end ? 'Yes' : 'No'}</span>
            </div>
            {subscription.provider === 'apple' && (
              <>
                <div className="flex justify-between">
                  <span className="text-text-secondary">Original Transaction ID:</span>
                  <span className="font-mono text-xs">
                    {subscription.apple_original_transaction_id ?? 'N/A'}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-text-secondary">Environment:</span>
                  <span>{subscription.apple_environment ?? 'N/A'}</span>
                </div>
              </>
            )}
            {subscription.provider === 'stripe' && (
              <>
                <div className="flex justify-between">
                  <span className="text-text-secondary">Stripe Customer ID:</span>
                  <span className="font-mono text-xs">
                    {subscription.stripe_customer_id ?? 'N/A'}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-text-secondary">Stripe Subscription ID:</span>
                  <span className="font-mono text-xs">
                    {subscription.stripe_subscription_id ?? 'N/A'}
                  </span>
                </div>
              </>
            )}
          </div>
        ) : (
          <p className="text-text-secondary">No subscription record</p>
        )}
      </Card>

      {/* App Account Token */}
      <Card className="p-4">
        <h2 className="text-lg font-semibold mb-4">App Account Token (Apple IAP)</h2>
        {appAccountToken ? (
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-text-secondary">Token:</span>
              <span className="font-mono text-xs">{appAccountToken.token}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-text-secondary">Created:</span>
              <span>{new Date(appAccountToken.created_at).toLocaleString()}</span>
            </div>
          </div>
        ) : (
          <p className="text-text-secondary">No app account token (will be created on first iOS purchase)</p>
        )}
      </Card>

      {/* Recent Apple Notifications */}
      {subscription?.provider === 'apple' && (
        <Card className="p-4">
          <h2 className="text-lg font-semibold mb-4">Recent Apple Notifications</h2>
          {recentNotifications && recentNotifications.length > 0 ? (
            <div className="space-y-3">
              {recentNotifications.map((notif: any) => (
                <div key={notif.id} className="text-sm border-b border-border pb-2">
                  <div className="flex justify-between">
                    <span className="font-medium">{notif.notification_type}</span>
                    <span className="text-text-secondary text-xs">
                      {new Date(notif.received_at).toLocaleString()}
                    </span>
                  </div>
                  {notif.subtype && (
                    <div className="text-text-secondary text-xs">Subtype: {notif.subtype}</div>
                  )}
                  <div className="text-text-secondary text-xs">
                    Processed: {notif.processed_at ? 'Yes' : 'No'}
                    {notif.last_error && <span className="text-red-500"> - Error: {notif.last_error}</span>}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-text-secondary">No recent notifications</p>
          )}
        </Card>
      )}

      {/* Profile */}
      <Card className="p-4">
        <h2 className="text-lg font-semibold mb-4">Profile</h2>
        <pre className="text-xs bg-surface-secondary p-3 rounded overflow-auto">
          {JSON.stringify(profile, null, 2)}
        </pre>
      </Card>
    </div>
  );
}
