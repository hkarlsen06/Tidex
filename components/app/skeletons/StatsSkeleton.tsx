import { Card } from "../Card";

export function StatsSkeleton() {
  return (
    <div className="mx-auto max-w-[800px] space-y-6 pb-8">
      {/* Month picker skeleton */}
      <div className="flex items-center justify-center gap-4 py-4">
        <div className="h-10 w-10 bg-surface-secondary rounded-lg animate-pulse" />
        <div className="h-8 w-32 bg-surface-secondary rounded animate-pulse" />
        <div className="h-10 w-10 bg-surface-secondary rounded-lg animate-pulse" />
      </div>

      {/* Summary stats cards */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {Array.from({ length: 3 }, (_, i) => (
          <Card key={i} className="rounded-card border-0 p-6 animate-pulse">
            <div className="space-y-3">
              <div className="h-4 w-24 bg-surface-secondary rounded" />
              <div className="h-8 w-32 bg-surface-secondary rounded" />
            </div>
          </Card>
        ))}
      </div>

      {/* Chart skeletons */}
      <div className="space-y-6">
        {Array.from({ length: 3 }, (_, i) => (
          <Card key={i} className="rounded-card border-0 p-6 animate-pulse">
            <div className="space-y-4">
              <div className="h-6 w-48 bg-surface-secondary rounded" />
              <div className="h-64 bg-surface-secondary rounded" />
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}
