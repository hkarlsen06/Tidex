import { Card, CardHeader } from "@/components/app/Card";

/**
 * Skeleton for ShiftCard
 * Matches the actual card structure: date/time on left, amount/breakdown on right
 */
export function ShiftCardSkeleton() {
  return (
    <Card className="bg-surface-primary rounded-3xl">
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-6">
        <div className="space-y-1">
          {/* Date + day (e.g., "15. januar · onsdag") */}
          <div className="h-7 w-44 bg-surface-secondary rounded animate-pulse" />
          {/* Clock icon + time range + arrow + hours */}
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-1">
              <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse" />
              <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse" />
            </div>
            <div className="h-4 w-3 bg-surface-secondary rounded animate-pulse" />
            <div className="h-4 w-10 bg-surface-secondary rounded animate-pulse" />
          </div>
        </div>
        <div className="text-right space-y-1">
          {/* Amount (e.g., "1 850 kr") */}
          <div className="h-8 w-20 bg-surface-secondary rounded animate-pulse" />
          {/* Breakdown (e.g., "1 500 + 350") */}
          <div className="h-3 w-16 bg-surface-secondary rounded animate-pulse ml-auto" />
        </div>
      </CardHeader>
    </Card>
  );
}
