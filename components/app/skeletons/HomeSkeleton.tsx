import { TotalCardSkeleton } from "../TotalCardSkeleton";
import { NextPayrollCardSkeleton } from "../NextPayrollCardSkeleton";
import { ShiftCardSkeleton } from "../ShiftCardSkeleton";

export function HomeSkeleton() {
  return (
    <div className="flex items-center justify-center h-full">
      <div className="flex flex-col gap-6 w-full max-w-md">
        {/* NextPayrollCard first (match actual order) */}
        <NextPayrollCardSkeleton />

        {/* TotalCard second */}
        <TotalCardSkeleton />

        {/* Month picker in middle (match actual position) */}
        <div className="flex items-center justify-between -mt-3 -mb-3">
          <div className="flex items-center gap-4">
            <div className="h-10 w-10 bg-surface-secondary rounded-lg animate-pulse" />
            <div className="h-8 w-32 bg-surface-secondary rounded animate-pulse" />
            <div className="h-10 w-10 bg-surface-secondary rounded-lg animate-pulse" />
          </div>
          <div className="h-5 w-12 bg-surface-secondary rounded animate-pulse mr-3" />
        </div>

        {/* Single shift with relative time text */}
        <div className="flex flex-col gap-2">
          <ShiftCardSkeleton />
          <div className="h-3 w-20 bg-surface-secondary rounded animate-pulse mx-auto" />
        </div>
      </div>
    </div>
  );
}
