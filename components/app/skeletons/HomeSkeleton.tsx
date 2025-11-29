import { Card, CardContent, CardHeader } from "@/components/app/Card";

/**
 * Skeleton for NextPayrollCard
 * Matches the actual card structure: date/label on left, amount/breakdown on right
 */
function NextPayrollCardSkeleton() {
  return (
    <Card className="bg-surface-primary rounded-3xl">
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-6">
        <div className="space-y-1">
          {/* Date (e.g., "15. januar") */}
          <div className="h-7 w-28 bg-surface-secondary rounded animate-pulse" />
          {/* Calendar icon + payroll label */}
          <div className="flex items-center gap-1">
            <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse" />
            <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse" />
          </div>
        </div>
        <div className="text-right space-y-1">
          {/* Amount (e.g., "12 500 kr") */}
          <div className="h-8 w-24 bg-surface-secondary rounded animate-pulse" />
          {/* Breakdown (e.g., "15 000 - 2 500") */}
          <div className="h-3 w-20 bg-surface-secondary rounded animate-pulse ml-auto" />
        </div>
      </CardHeader>
    </Card>
  );
}

/**
 * Skeleton for TotalCard
 * Matches the actual card structure: centered percentage, large amount, subtitle
 */
function TotalCardSkeleton() {
  return (
    <Card className="bg-surface-primary rounded-3xl">
      <CardContent className="py-6">
        <div className="text-center">
          {/* Percentage change indicator */}
          <div className="flex items-center justify-center gap-2">
            <div className="h-6 w-6 bg-surface-secondary rounded animate-pulse" />
            <div className="h-6 w-12 bg-surface-secondary rounded animate-pulse" />
          </div>
          {/* Large total amount */}
          <div className="mt-3">
            <div className="h-16 w-48 bg-surface-secondary rounded mx-auto animate-pulse" />
          </div>
          {/* Subtitle (projected total or gross before tax) */}
          <div className="mt-4">
            <div className="h-5 w-40 bg-surface-secondary rounded mx-auto animate-pulse" />
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

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
 * Skeleton for ShiftCard
 * Matches the actual card structure: date/time on left, amount/breakdown on right
 */
function ShiftCardSkeleton() {
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
