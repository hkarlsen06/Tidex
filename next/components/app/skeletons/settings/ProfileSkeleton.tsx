import { Card } from "@/components/app/Card";

/**
 * ProfileSkeleton - Loading skeleton for /settings/profile
 * Matches: Title + subtitle, ProfileForm (avatar + fields), DangerZone card
 *
 * Note: Uses static layout matching SettingsPageWrapper to avoid client component
 * hydration delays in loading.tsx files.
 */
export function ProfileSkeleton() {
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

            {/* ProfileForm Card */}
            <Card className="p-6">
              <div className="space-y-6">
                <div className="space-y-5">
                  <div className="space-y-4">
                    {/* Section title */}
                    <div className="h-7 w-48 bg-surface-secondary rounded animate-pulse" />

                    {/* Avatar row */}
                    <div className="flex items-center gap-6">
                      {/* Avatar */}
                      <div className="h-24 w-24 rounded-full bg-surface-secondary animate-pulse" />
                      {/* Upload buttons */}
                      <div className="flex flex-col items-center gap-3">
                        <div className="h-9 w-36 bg-surface-secondary rounded-md animate-pulse" />
                      </div>
                    </div>
                  </div>

                  {/* Name field */}
                  <div className="space-y-2">
                    <div className="h-4 w-12 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-10 w-full bg-surface-secondary rounded-md border border-border animate-pulse" />
                  </div>

                  {/* Email field */}
                  <div className="space-y-2">
                    <div className="h-4 w-16 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-10 w-full bg-surface-secondary rounded-md border border-border animate-pulse" />
                    <div className="h-3 w-24 bg-surface-secondary rounded animate-pulse" />
                  </div>
                </div>
              </div>
            </Card>

            {/* DangerZone Card */}
            <div className="pt-4">
              <Card className="p-6 border-red-200 dark:border-red-900">
                <div className="space-y-4">
                  <div>
                    <div className="h-5 w-24 bg-red-100 dark:bg-red-900/30 rounded animate-pulse" />
                    <div className="h-4 w-72 bg-surface-secondary rounded animate-pulse mt-1" />
                  </div>

                  <div className="h-px bg-border" />

                  <div className="flex flex-col gap-3 sm:flex-row sm:items-stretch sm:gap-8">
                    <div className="space-y-1 sm:w-52 sm:shrink-0">
                      <div className="h-5 w-32 bg-surface-secondary rounded animate-pulse" />
                      <div className="h-4 w-40 bg-surface-secondary rounded animate-pulse" />
                    </div>
                    <div className="h-12 w-full sm:w-40 bg-red-100 dark:bg-red-900/30 rounded-md animate-pulse" />
                  </div>
                </div>
              </Card>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
