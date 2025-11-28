import { Card } from "@/components/app/Card";

/**
 * DisplaySkeleton - Loading skeleton for /settings/display
 * Matches: Title + subtitle, DisplayForm (theme + view cards), CurrencySelector card
 *
 * Note: Uses static layout matching SettingsPageWrapper to avoid client component
 * hydration delays in loading.tsx files.
 */
export function DisplaySkeleton() {
  return (
    <div className="h-full overflow-y-auto pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8">
      <div className="mx-auto max-w-md md:max-w-lg px-4 w-full">
        <div className="py-8">
          <div className="space-y-6">
            {/* Title and subtitle */}
            <div>
              <div className="h-8 w-24 bg-surface-secondary rounded animate-pulse" />
              <div className="h-5 w-64 bg-surface-secondary rounded animate-pulse mt-1" />
            </div>

            {/* DisplayForm - Theme Card */}
            <Card className="p-6">
              <div className="space-y-6">
                <div className="space-y-4">
                  <div>
                    <div className="h-5 w-16 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-4 w-56 bg-surface-secondary rounded animate-pulse mb-4 mt-1" />
                    {/* Theme buttons row */}
                    <div className="flex gap-2 sm:gap-4">
                      {/* Light */}
                      <div className="flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 border-2 border-border">
                        <div className="h-8 w-8 bg-surface-secondary rounded animate-pulse" />
                        <div className="h-3 w-8 bg-surface-secondary rounded animate-pulse" />
                      </div>
                      {/* Dark */}
                      <div className="flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 border-2 border-border">
                        <div className="h-8 w-8 bg-surface-secondary rounded animate-pulse" />
                        <div className="h-3 w-8 bg-surface-secondary rounded animate-pulse" />
                      </div>
                      {/* System */}
                      <div className="flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 border-2 border-border">
                        <div className="h-8 w-8 bg-surface-secondary rounded animate-pulse" />
                        <div className="h-3 w-10 bg-surface-secondary rounded animate-pulse" />
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </Card>

            {/* DisplayForm - Default View Card */}
            <Card className="p-6">
              <div className="space-y-6">
                <div className="space-y-4">
                  <div>
                    <div className="h-5 w-32 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-4 w-72 bg-surface-secondary rounded animate-pulse mb-4 mt-1" />
                    {/* View buttons row */}
                    <div className="flex gap-2 sm:gap-4">
                      {/* Calendar */}
                      <div className="flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 border-2 border-border">
                        <div className="h-8 w-8 bg-surface-secondary rounded animate-pulse" />
                        <div className="h-3 w-12 bg-surface-secondary rounded animate-pulse" />
                      </div>
                      {/* List */}
                      <div className="flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 border-2 border-border">
                        <div className="h-8 w-8 bg-surface-secondary rounded animate-pulse" />
                        <div className="h-3 w-8 bg-surface-secondary rounded animate-pulse" />
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </Card>

            {/* CurrencySelector Card */}
            <Card className="p-6">
              <div className="space-y-4">
                <div>
                  <div className="h-5 w-20 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-4 w-64 bg-surface-secondary rounded animate-pulse mb-4 mt-1" />
                  {/* Select dropdown */}
                  <div className="h-10 w-full max-w-xs bg-surface-secondary rounded-md border border-border animate-pulse" />
                </div>
              </div>
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}
