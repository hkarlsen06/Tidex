import { NextPayrollCardSkeleton } from "../cards/NextPayrollCardSkeleton";
import { TotalCardSkeleton } from "../cards/TotalCardSkeleton";
import { ShiftCardSkeleton } from "../cards/ShiftCardSkeleton";

/**
 * Skeleton for MonthPicker
 * Matches: prev button, month name, next button, year on right
 */
function MonthPickerSkeleton() {
  return (
    <div className="flex items-center justify-between -mt-3 -mb-3">
      <div className="flex items-center gap-4">
        {/* Previous month button */}
        <div className="h-10 w-10 bg-surface-secondary rounded-lg animate-pulse" />
        {/* Month name */}
        <div className="h-8 w-28 bg-surface-secondary rounded animate-pulse" />
        {/* Next month button */}
        <div className="h-10 w-10 bg-surface-secondary rounded-lg animate-pulse" />
      </div>
      {/* Year */}
      <div className="h-5 w-12 bg-surface-secondary rounded animate-pulse mr-3" />
    </div>
  );
}

/**
 * HomeSkeleton - Loading skeleton for the dashboard/home page
 * Matches the actual HomeContent layout inside CenteredPageWrapper
 */
export function HomeSkeleton() {
  return (
    <div className="h-full px-4 pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8 overflow-y-auto">
      <div className="w-full max-w-md md:max-w-lg mx-auto my-auto min-h-full flex flex-col justify-center pt-2 pb-6">
        <div className="flex items-center">
          <div className="flex flex-col gap-6 w-full">
            {/* Payroll countdown text */}
            <div className="flex flex-col gap-2">
              <div className="h-3 w-32 bg-surface-secondary rounded animate-pulse mx-auto" />
              <NextPayrollCardSkeleton />
            </div>

            {/* Total earnings card */}
            <TotalCardSkeleton />

            {/* Month picker */}
            <MonthPickerSkeleton />

            {/* Display shift with relative time */}
            <div className="flex flex-col gap-2">
              <ShiftCardSkeleton />
              {/* Relative time text (e.g., "om 2 dager") */}
              <div className="h-3 w-20 bg-surface-secondary rounded animate-pulse mx-auto" />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
