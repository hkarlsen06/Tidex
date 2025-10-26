import { NextPayrollCardSkeleton } from "@/components/app/NextPayrollCardSkeleton";
import { TotalCardSkeleton } from "@/components/app/TotalCardSkeleton";
import { ShiftCardSkeleton } from "@/components/app/ShiftCardSkeleton";

export default function HomeLoading() {
  return (
    <div className="flex items-center justify-center h-full">
      <div className="flex flex-col gap-6 w-full max-w-md">
        <NextPayrollCardSkeleton />
        <TotalCardSkeleton />

        {/* Month picker skeleton */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="h-8 w-8 bg-surface-secondary rounded-full animate-pulse" />
            <div className="h-6 w-24 bg-surface-secondary rounded animate-pulse" />
            <div className="h-8 w-8 bg-surface-secondary rounded-full animate-pulse" />
          </div>
          <div className="h-6 w-16 bg-surface-secondary rounded animate-pulse" />
        </div>

        {/* Shift card skeleton */}
        <div className="flex flex-col gap-2">
          <ShiftCardSkeleton />
          <div className="h-3 w-24 bg-surface-secondary rounded animate-pulse mx-auto" />
        </div>
      </div>
    </div>
  );
}
