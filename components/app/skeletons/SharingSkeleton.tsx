import { Card, CardHeader } from "@/components/app/Card";

/**
 * Skeleton for the calendar component (reused from ShiftsSkeleton)
 */
function CalendarSkeleton() {
  return (
    <Card className="rounded-3xl border-0 bg-transparent">
      {/* Calendar header: month picker + year + total */}
      <div className="flex flex-row items-center justify-between py-3">
        <div className="flex items-center gap-1 flex-1">
          {/* Month picker: prev button, month name, next button */}
          <div className="flex items-center gap-2">
            <div className="h-9 w-9 bg-surface-secondary rounded animate-pulse" />
            <div className="h-6 w-24 bg-surface-secondary rounded animate-pulse" />
            <div className="h-9 w-9 bg-surface-secondary rounded animate-pulse" />
          </div>
          {/* Year */}
          <div className="h-5 w-12 bg-surface-secondary rounded animate-pulse ml-1" />
        </div>
        {/* Total earnings for month */}
        <div className="h-6 w-20 bg-surface-secondary rounded animate-pulse" />
      </div>

      {/* Weekday headers (M T W T F S S) */}
      <div className="grid grid-cols-7 mb-2">
        {Array.from({ length: 7 }, (_, i) => (
          <div key={i} className="text-center py-2">
            <div className="h-3 w-6 bg-surface-secondary rounded animate-pulse mx-auto" />
          </div>
        ))}
      </div>

      {/* Calendar grid - 5 weeks x 7 days */}
      <div className="space-y-1 pb-6">
        {Array.from({ length: 5 }, (_, weekIdx) => (
          <div key={weekIdx} className="grid grid-cols-7 gap-1">
            {Array.from({ length: 7 }, (_, dayIdx) => {
              const cellIdx = weekIdx * 7 + dayIdx;
              // Simulate some days having shifts (every 2-3 days)
              const hasShift = cellIdx % 3 === 0;

              return (
                <div key={dayIdx} className="aspect-square p-0">
                  <div className="w-full h-full rounded-lg border border-border-subtle bg-surface-primary p-1 pb-1.5">
                    <div className="relative flex flex-col items-center justify-start gap-0.5 w-full h-full">
                      {/* Day number */}
                      <div className="w-full text-right pr-1">
                        <div className="h-3 w-4 bg-surface-secondary rounded animate-pulse ml-auto" />
                      </div>
                      {/* Earnings placeholder (only for days with "shifts") */}
                      {hasShift && (
                        <div className="h-3 w-10 bg-surface-secondary rounded animate-pulse mt-1" />
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        ))}
      </div>

      {/* Toggle buttons for earnings/hours view */}
      <div className="flex justify-center pb-6">
        <div className="inline-flex items-center gap-1 rounded-full border border-border-subtle bg-surface-secondary/80 p-1 w-2/3">
          <div className="h-9 flex-1 bg-surface-primary rounded-full animate-pulse" />
          <div className="h-9 flex-1 bg-surface-secondary rounded-full animate-pulse" />
        </div>
      </div>
    </Card>
  );
}

/**
 * Skeleton for a shift card in the list
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
          {/* Amount */}
          <div className="h-8 w-20 bg-surface-secondary rounded animate-pulse" />
          {/* Breakdown */}
          <div className="h-3 w-16 bg-surface-secondary rounded animate-pulse ml-auto" />
        </div>
      </CardHeader>
    </Card>
  );
}

/**
 * Skeleton for a week group in the shifts list
 */
function WeekGroupSkeleton({ shiftCount }: { shiftCount: number }) {
  return (
    <section className="space-y-4">
      {/* Week header: "Uke X" + chevron + total */}
      <div className="flex flex-row items-center justify-between bg-transparent">
        <div className="flex items-center gap-2">
          <div className="h-5 w-16 bg-surface-secondary rounded animate-pulse" />
          <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse" />
        </div>
        <div className="h-5 w-20 bg-surface-secondary rounded animate-pulse" />
      </div>
      {/* Shift cards */}
      <div className="space-y-4">
        {Array.from({ length: shiftCount }, (_, i) => (
          <ShiftCardSkeleton key={i} />
        ))}
      </div>
    </section>
  );
}

/**
 * Skeleton for the sharing page header with dropdown and settings button
 */
function SharingHeaderSkeleton() {
  return (
    <div className="flex items-center gap-2 w-full sm:justify-between sm:gap-3 px-4 py-2">
      {/* Dropdown skeleton */}
      <div className="h-10 w-48 bg-surface-secondary rounded-lg animate-pulse flex-1 max-w-[200px]" />
      {/* Settings button skeleton */}
      <div className="h-9 w-9 sm:w-32 bg-surface-secondary rounded-lg animate-pulse shrink-0" />
    </div>
  );
}

/**
 * SharingSkeleton - Loading skeleton for the /sharing page
 * Shows when navigating between sharing views (e.g., selecting a different sharer)
 */
export function SharingSkeleton() {
  return (
    <div className="h-full overflow-y-auto pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8">
      {/* Header with dropdown and settings */}
      <SharingHeaderSkeleton />

      {/* Mobile/Tablet: vertical stack. Desktop: side-by-side */}
      <div className="flex w-full flex-col lg:relative lg:left-1/2 lg:right-1/2 lg:-ml-[50vw] lg:-mr-[50vw] lg:w-screen lg:flex-row lg:gap-0 lg:px-0 lg:items-start lg:pt-6">
        {/* Calendar Section */}
        <div className="h-[calc(100dvh-3.5rem-5rem-env(safe-area-inset-top)-env(safe-area-inset-bottom))] flex flex-col justify-center px-4 shrink-0 lg:h-auto lg:w-1/2 lg:sticky lg:top-6 lg:justify-start lg:items-center lg:px-0">
          <div className="w-full max-w-md md:max-w-lg lg:max-w-none lg:w-[480px]">
            <CalendarSkeleton />
          </div>
        </div>

        {/* Shifts List Section */}
        <div className="px-4 lg:w-1/2 lg:flex lg:justify-center lg:px-0">
          <div className="pb-10 w-full max-w-md md:max-w-lg lg:max-w-lg lg:overflow-y-auto lg:max-h-[calc(100vh-8rem)] lg:px-4">
            <div className="flex flex-col gap-12">
              {/* Week groups with varying shift counts */}
              <WeekGroupSkeleton shiftCount={2} />
              <WeekGroupSkeleton shiftCount={3} />
              <WeekGroupSkeleton shiftCount={1} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
