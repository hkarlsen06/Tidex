import { Card } from "@/components/app/Card";

/**
 * StatsSkeleton - Loading skeleton for the /stats page
 * Matches the actual StatsContent layout
 */
export function StatsSkeleton() {
  return (
    <div className="flex flex-col w-full max-w-md mx-auto pb-6 pt-2 space-y-6">
      {/* Hero section with key metrics */}
      <div className="space-y-5">
        {/* Month picker with year */}
        <div className="flex items-center justify-between -mb-3">
          <div className="flex items-center gap-4">
            <div className="h-10 w-10 bg-surface-secondary rounded-lg animate-pulse" />
            <div className="h-8 w-32 bg-surface-secondary rounded animate-pulse" />
            <div className="h-10 w-10 bg-surface-secondary rounded-lg animate-pulse" />
          </div>
          <div className="h-5 w-12 bg-surface-secondary rounded animate-pulse mr-3" />
        </div>

        {/* Hero earnings card */}
        <Card className="border-border bg-surface-primary overflow-hidden">
          <div className="p-6 space-y-3">
            <div className="h-5 w-48 bg-surface-secondary rounded animate-pulse" />
            <div className="flex items-baseline gap-2">
              <div className="h-12 w-32 bg-surface-secondary rounded animate-pulse" />
              <div className="h-6 w-8 bg-surface-secondary rounded animate-pulse" />
            </div>
          </div>
        </Card>

        {/* Hours/Shifts grid */}
        <div className="grid grid-cols-2 gap-3">
          {Array.from({ length: 2 }, (_, i) => (
            <Card
              key={i}
              className="border-border bg-surface-primary overflow-hidden"
            >
              <div className="p-5 space-y-3">
                <div className="h-4 w-16 bg-surface-secondary rounded animate-pulse" />
                <div className="h-8 w-20 bg-surface-secondary rounded animate-pulse" />
              </div>
            </Card>
          ))}
        </div>
      </div>

      {/* Monthly goal progress placeholder */}
      <Card className="border-border bg-surface-primary">
        <div className="p-5 space-y-3">
          <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse" />
          <div className="h-2 w-full bg-surface-secondary rounded-full animate-pulse" />
        </div>
      </Card>

      {/* Chart skeletons */}
      <div className="space-y-5">
        {Array.from({ length: 2 }, (_, i) => (
          <Card key={i} className="border-border bg-surface-primary">
            <div className="p-5 space-y-3">
              <div className="h-6 w-32 bg-surface-secondary rounded animate-pulse" />
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </div>
          </Card>
        ))}
      </div>

      {/* Average hourly rate */}
      <Card className="border-border bg-surface-primary overflow-hidden">
        <div className="p-5 space-y-3">
          <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse" />
          <div className="flex items-baseline gap-1.5">
            <div className="h-8 w-20 bg-surface-secondary rounded animate-pulse" />
            <div className="h-6 w-12 bg-surface-secondary rounded animate-pulse" />
          </div>
        </div>
      </Card>

      {/* Year to date summary */}
      <div className="space-y-5">
        <div className="h-6 w-24 bg-surface-secondary rounded animate-pulse pl-6" />

        {/* Year charts */}
        {Array.from({ length: 3 }, (_, i) => (
          <Card key={i} className="border-border bg-surface-primary">
            <div className="p-5 space-y-3">
              <div className="h-6 w-32 bg-surface-secondary rounded animate-pulse" />
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </div>
          </Card>
        ))}

        {/* YTD stats */}
        <div className="grid grid-cols-1 gap-3">
          {Array.from({ length: 3 }, (_, i) => (
            <Card
              key={i}
              className="border-border bg-surface-primary overflow-hidden"
            >
              <div className="p-5 space-y-3">
                <div className="h-4 w-16 bg-surface-secondary rounded animate-pulse" />
                <div className="flex items-baseline gap-1.5">
                  <div className="h-8 w-24 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-6 w-8 bg-surface-secondary rounded animate-pulse" />
                </div>
              </div>
            </Card>
          ))}
        </div>
      </div>
    </div>
  );
}
