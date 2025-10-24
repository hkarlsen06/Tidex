import { TotalCardSkeleton } from "../TotalCardSkeleton";
import { NextPayrollCardSkeleton } from "../NextPayrollCardSkeleton";
import { ShiftCardSkeleton } from "../ShiftCardSkeleton";

export function HomeSkeleton() {
  return (
    <div className="mx-auto max-w-[800px] space-y-6">
      {/* Month picker skeleton */}
      <div className="flex items-center justify-center gap-4 py-4">
        <div className="h-10 w-10 bg-surface-secondary rounded-lg animate-pulse" />
        <div className="h-8 w-32 bg-surface-secondary rounded animate-pulse" />
        <div className="h-10 w-10 bg-surface-secondary rounded-lg animate-pulse" />
      </div>

      {/* Summary cards */}
      <div className="grid gap-4 sm:grid-cols-2">
        <TotalCardSkeleton />
        <NextPayrollCardSkeleton />
      </div>

      {/* Recent shifts skeleton */}
      <div className="space-y-4">
        <div className="h-6 w-32 bg-surface-secondary rounded animate-pulse" />
        <div className="space-y-3">
          <ShiftCardSkeleton />
          <ShiftCardSkeleton />
          <ShiftCardSkeleton />
        </div>
      </div>
    </div>
  );
}
