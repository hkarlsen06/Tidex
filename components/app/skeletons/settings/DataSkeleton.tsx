/**
 * DataSkeleton - Loading skeleton for /settings/data
 * Matches: DataForm layout (title, period selection, export buttons)
 *
 * Note: Uses static layout matching SettingsPageWrapper to avoid client component
 * hydration delays in loading.tsx files.
 */
export function DataSkeleton() {
  return (
    <div className="h-full overflow-y-auto pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8">
      <div className="mx-auto max-w-md md:max-w-lg px-4 w-full">
        <div className="py-8">
          <div className="mt-6">
            <div className="space-y-6">
              <div className="space-y-6">
                {/* Title centered */}
                <div className="text-center">
                  <div className="h-6 w-36 bg-surface-secondary rounded animate-pulse mx-auto" />
                  <div className="h-4 w-64 bg-surface-secondary rounded animate-pulse mx-auto mt-1" />
                </div>

                {/* Separator */}
                <div className="h-px bg-border" />

                <div className="space-y-4">
                  {/* Period label */}
                  <div>
                    <div className="h-5 w-32 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-4 w-56 bg-surface-secondary rounded animate-pulse mt-1" />
                  </div>

                  {/* Preset buttons row */}
                  <div className="flex gap-2">
                    <div className="flex-1 min-w-0 h-10 bg-surface-secondary rounded-md animate-pulse" />
                    <div className="flex-1 min-w-0 h-10 bg-surface-secondary rounded-md animate-pulse" />
                    <div className="flex-1 min-w-0 h-10 bg-surface-secondary rounded-md animate-pulse" />
                  </div>

                  {/* Or divider */}
                  <div className="flex items-center gap-4">
                    <div className="h-px flex-1 bg-border" />
                    <div className="h-3 w-8 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-px flex-1 bg-border" />
                  </div>

                  {/* Custom period box */}
                  <div className="w-full rounded-md border border-border p-3 sm:p-4">
                    <div className="flex flex-col gap-2">
                      <div className="flex flex-wrap items-center gap-2 sm:gap-3">
                        <div className="h-5 w-28 bg-surface-secondary rounded animate-pulse" />
                        <div className="flex flex-wrap items-center gap-2 sm:flex-nowrap">
                          <div className="flex items-center gap-2">
                            <div className="h-3 w-8 bg-surface-secondary rounded animate-pulse" />
                            <div className="h-10 w-32 sm:w-36 bg-surface-secondary rounded-md border border-border animate-pulse" />
                          </div>
                          <div className="flex items-center gap-2">
                            <div className="h-3 w-6 bg-surface-secondary rounded animate-pulse" />
                            <div className="h-10 w-32 sm:w-36 bg-surface-secondary rounded-md border border-border animate-pulse" />
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Separator */}
                <div className="h-px bg-border" />

                {/* Export options */}
                <div className="space-y-6">
                  {/* PDF export row */}
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                    <div>
                      <div className="h-5 w-24 bg-surface-secondary rounded animate-pulse" />
                      <div className="h-4 w-56 bg-surface-secondary rounded animate-pulse mt-1" />
                    </div>
                    <div className="h-10 w-full sm:w-36 bg-red-100 dark:bg-red-900/20 rounded-md animate-pulse" />
                  </div>

                  {/* CSV export row */}
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                    <div>
                      <div className="h-5 w-24 bg-surface-secondary rounded animate-pulse" />
                      <div className="h-4 w-48 bg-surface-secondary rounded animate-pulse mt-1" />
                    </div>
                    <div className="h-10 w-full sm:w-36 bg-surface-secondary rounded-md animate-pulse" />
                  </div>
                </div>
              </div>

              {/* Separator */}
              <div className="h-px bg-border mt-6" />

              {/* About section */}
              <div className="space-y-2">
                <div className="h-5 w-20 bg-surface-secondary rounded animate-pulse" />
                <div className="h-4 w-full bg-surface-secondary rounded animate-pulse" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
