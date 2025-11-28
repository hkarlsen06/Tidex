import { Card } from "@/components/app/Card";

/**
 * SubscriptionSkeleton - Loading skeleton for /settings/subscription
 * Matches: Title + subtitle, status/plan info card, UpgradeOptions with plan cards
 *
 * Note: Uses static layout matching SettingsPageWrapper to avoid client component
 * hydration delays in loading.tsx files.
 */
export function SubscriptionSkeleton() {
  return (
    <div className="h-full overflow-y-auto pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8">
      <div className="mx-auto max-w-md md:max-w-lg px-4 w-full">
        <div className="py-8">
          <div className="space-y-6">
            {/* Title and subtitle */}
            <div>
              <div className="h-8 w-32 bg-surface-secondary rounded animate-pulse" />
              <div className="h-5 w-72 bg-surface-secondary rounded animate-pulse mt-1" />
            </div>

            {/* Free plan info / status card */}
            <Card className="p-6">
              <div className="space-y-4">
                <div className="h-6 w-28 bg-surface-secondary rounded animate-pulse" />
                <div className="h-4 w-full bg-surface-secondary rounded animate-pulse" />
                <div className="h-4 w-3/4 bg-surface-secondary rounded animate-pulse" />
              </div>
            </Card>

            {/* UpgradeOptions */}
            <div className="space-y-6">
              {/* Section title */}
              <div>
                <div className="h-6 w-40 bg-surface-secondary rounded animate-pulse mb-2" />
                <div className="h-4 w-64 bg-surface-secondary rounded animate-pulse" />
              </div>

              {/* Billing period tabs */}
              <div className="flex justify-center">
                <div className="h-10 w-56 bg-surface-secondary rounded-md animate-pulse" />
              </div>

              {/* Plan cards */}
              <div className="flex flex-col gap-6">
                {/* Pro Plan Card */}
                <Card className="p-6 relative border-2 border-text-primary">
                  {/* Popular badge */}
                  <div className="absolute -top-3 left-1/2 -translate-x-1/2">
                    <div className="h-6 w-20 bg-text-primary rounded-full animate-pulse" />
                  </div>

                  <div className="space-y-6">
                    <div>
                      <div className="h-8 w-12 bg-surface-secondary rounded animate-pulse" />
                      <div className="h-4 w-48 bg-surface-secondary rounded animate-pulse mt-1" />
                    </div>

                    <div className="space-y-2">
                      <div className="flex items-baseline gap-1">
                        <div className="h-10 w-20 bg-surface-secondary rounded animate-pulse" />
                        <div className="h-4 w-12 bg-surface-secondary rounded animate-pulse" />
                      </div>
                    </div>

                    <div className="h-px bg-border" />

                    <div className="space-y-3">
                      {[1, 2, 3, 4].map((i) => (
                        <div key={i} className="flex gap-3 items-start">
                          <div className="h-5 w-5 bg-green-100 dark:bg-green-900/30 rounded animate-pulse shrink-0 mt-0.5" />
                          <div className="h-4 w-48 bg-surface-secondary rounded animate-pulse" />
                        </div>
                      ))}
                    </div>

                    <div className="h-10 w-full bg-surface-secondary rounded-md animate-pulse" />
                  </div>
                </Card>

                {/* Max Plan Card */}
                <Card className="p-6">
                  <div className="space-y-6">
                    <div>
                      <div className="h-8 w-12 bg-surface-secondary rounded animate-pulse" />
                      <div className="h-4 w-56 bg-surface-secondary rounded animate-pulse mt-1" />
                    </div>

                    <div className="space-y-2">
                      <div className="flex items-baseline gap-1">
                        <div className="h-10 w-24 bg-surface-secondary rounded animate-pulse" />
                        <div className="h-4 w-12 bg-surface-secondary rounded animate-pulse" />
                      </div>
                    </div>

                    <div className="h-px bg-border" />

                    <div className="space-y-3">
                      {[1, 2, 3, 4, 5].map((i) => (
                        <div key={i} className="flex gap-3 items-start">
                          <div className="h-5 w-5 bg-green-100 dark:bg-green-900/30 rounded animate-pulse shrink-0 mt-0.5" />
                          <div className="h-4 w-52 bg-surface-secondary rounded animate-pulse" />
                        </div>
                      ))}
                    </div>

                    <div className="h-10 w-full bg-surface-secondary rounded-md border border-border animate-pulse" />
                  </div>
                </Card>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
