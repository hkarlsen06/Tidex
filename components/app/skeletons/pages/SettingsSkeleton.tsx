import { Card } from "@/components/app/Card";

/**
 * SettingsSkeleton - Loading skeleton for the /settings hub page
 * Matches the settings menu layout with 6 navigation cards
 *
 * Note: Uses static layout matching ScrollablePageWrapper to avoid client component
 * hydration delays in loading.tsx files.
 */
export function SettingsSkeleton() {
  return (
    <div className="h-full overflow-y-auto pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8">
      <div className="mx-auto max-w-md md:max-w-lg px-4 w-full">
        <div className="py-8">
          {/* Title and subtitle */}
          <div className="h-9 w-36 bg-surface-secondary rounded animate-pulse mb-2" />
          <div className="h-5 w-64 bg-surface-secondary rounded animate-pulse mb-10" />

          {/* Settings menu cards */}
          <div className="flex flex-col gap-6">
            {Array.from({ length: 6 }, (_, i) => (
              <Card key={i} className="p-5">
                <div className="flex items-center gap-4">
                  {/* Icon placeholder */}
                  <div className="p-3 rounded-lg bg-surface-secondary">
                    <div className="h-6 w-6 bg-surface-primary rounded animate-pulse" />
                  </div>
                  {/* Text content */}
                  <div className="flex-1">
                    <div className="h-5 w-28 bg-surface-secondary rounded animate-pulse mb-1.5" />
                    <div className="h-4 w-48 bg-surface-secondary rounded animate-pulse" />
                  </div>
                  {/* Chevron */}
                  <div className="h-5 w-5 bg-surface-secondary rounded animate-pulse shrink-0" />
                </div>
              </Card>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
