import { Card } from "@/components/app/Card";
import { SettingsPageWrapper } from "@/components/app/SettingsPageWrapper";

/**
 * PaySkeleton - Loading skeleton for /settings/pay
 * Matches: Title + subtitle, WageHistoryTimeline, Separator, PayForm (3 cards)
 */
export function PaySkeleton() {
  return (
    <SettingsPageWrapper routeKey="settings-pay">
      <div className="space-y-6">
        {/* Title and subtitle */}
        <div>
          <div className="h-8 w-16 bg-surface-secondary rounded animate-pulse" />
          <div className="h-5 w-80 bg-surface-secondary rounded animate-pulse mt-1" />
        </div>

        {/* WageHistoryTimeline Card */}
        <div className="space-y-6">
          <Card className="overflow-hidden">
            {/* Header */}
            <div className="p-6 pb-4 flex items-center justify-between">
              <div className="h-6 w-32 bg-surface-secondary rounded animate-pulse" />
              <div className="h-9 w-9 md:w-24 bg-surface-secondary rounded-md animate-pulse" />
            </div>

            {/* Timeline */}
            <div className="relative px-6 pb-6">
              <div className="space-y-0 relative">
                {/* Current wage entry */}
                <div className="relative pb-4">
                  <div className="absolute left-0 top-0 bottom-0 w-0.5 bg-border z-5" />
                  <div className="relative">
                    <div className="absolute inset-0 -left-6 -right-6 bg-wage-current z-1" />
                    <div className="absolute left-px top-1/2 -translate-y-1/2 -translate-x-1/2 w-5 h-5 rounded-full bg-brand-gradient-start border-2 border-surface-secondary z-20" />
                    <div className="relative pl-6 pr-0 py-4 flex items-center justify-between gap-4 z-2">
                      <div className="flex-1 min-w-0">
                        <div className="h-8 w-32 bg-surface-secondary rounded animate-pulse" />
                        <div className="h-4 w-40 bg-surface-secondary rounded animate-pulse mt-1 ml-[1ch]" />
                      </div>
                      <div className="h-9 w-9 md:w-20 bg-surface-secondary rounded-md animate-pulse shrink-0" />
                    </div>
                  </div>
                </div>

                {/* Past wage entry */}
                <div className="relative pb-0">
                  <div className="absolute left-0 top-0 bottom-0 w-0.5 bg-border z-5" />
                  <div className="relative">
                    <div className="absolute left-px top-1/2 -translate-y-1/2 -translate-x-1/2 w-3 h-3 rounded-full bg-brand-gradient-start border-2 border-background z-20" />
                    <div className="relative pl-6 pr-0 py-2 flex items-center justify-between gap-4 z-2">
                      <div className="flex-1 min-w-0">
                        <div className="h-5 w-28 bg-surface-secondary rounded animate-pulse" />
                        <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse mt-1 ml-[1ch]" />
                      </div>
                      <div className="h-9 w-9 md:w-20 bg-surface-secondary rounded-md animate-pulse shrink-0" />
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </Card>

          {/* Tip box */}
          <div className="rounded-md bg-blue-50 dark:bg-blue-900/10 p-4">
            <div className="h-4 w-full bg-blue-100 dark:bg-blue-800/20 rounded animate-pulse" />
          </div>
        </div>

        {/* Separator */}
        <div className="h-px bg-border" />

        {/* PayForm - Break Deduction Card */}
        <Card className="p-6">
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <div>
                <div className="h-6 w-28 bg-surface-secondary rounded animate-pulse" />
                <div className="h-4 w-64 bg-surface-secondary rounded animate-pulse mt-1" />
              </div>
              <div className="h-6 w-11 bg-surface-secondary rounded-full animate-pulse" />
            </div>
          </div>
        </Card>

        {/* Tax Deduction Card */}
        <Card className="p-6">
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <div>
                <div className="h-6 w-24 bg-surface-secondary rounded animate-pulse" />
                <div className="h-4 w-56 bg-surface-secondary rounded animate-pulse mt-1" />
              </div>
              <div className="h-6 w-11 bg-surface-secondary rounded-full animate-pulse" />
            </div>
          </div>
        </Card>

        {/* Other Settings Card */}
        <Card className="p-6">
          <div className="space-y-6">
            <div>
              <div className="h-6 w-36 bg-surface-secondary rounded animate-pulse" />
              <div className="h-4 w-48 bg-surface-secondary rounded animate-pulse mt-1" />
            </div>

            <div className="h-px bg-border" />

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2">
                <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse" />
                <div className="h-10 w-full bg-surface-secondary rounded-md border border-border animate-pulse" />
              </div>
              <div className="space-y-2">
                <div className="h-4 w-28 bg-surface-secondary rounded animate-pulse" />
                <div className="h-10 w-full bg-surface-secondary rounded-md border border-border animate-pulse" />
              </div>
            </div>
          </div>
        </Card>
      </div>
    </SettingsPageWrapper>
  );
}
