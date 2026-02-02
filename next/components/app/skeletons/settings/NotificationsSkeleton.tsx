import { Card } from "@/components/app/Card";

/**
 * NotificationsSkeleton - Loading skeleton for /settings/notifications
 * Matches: Title + subtitle, NotificationSettingsForm card with toggle switch
 *
 * Note: Uses static layout matching SettingsPageWrapper to avoid client component
 * hydration delays in loading.tsx files.
 */
export function NotificationsSkeleton() {
  return (
    <div className="h-full overflow-y-auto pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8">
      <div className="mx-auto max-w-md md:max-w-lg px-4 w-full">
        <div className="py-8">
          <div className="space-y-6">
            {/* Title and subtitle */}
            <div>
              <div className="h-8 w-36 bg-surface-secondary rounded animate-pulse" />
              <div className="h-5 w-72 bg-surface-secondary rounded animate-pulse mt-1" />
            </div>

            {/* NotificationSettingsForm Card */}
            <Card className="p-6">
              <div className="space-y-6">
                {/* Shared shifts toggle */}
                <div className="flex items-center justify-between">
                  <div className="space-y-0.5 flex-1">
                    <div className="h-5 w-32 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-4 w-64 bg-surface-secondary rounded animate-pulse" />
                  </div>
                  <div className="h-6 w-11 bg-surface-secondary rounded-full animate-pulse" />
                </div>
              </div>
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}
