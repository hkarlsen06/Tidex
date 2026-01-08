import { Card } from "@/components/app/Card";

/**
 * Skeleton for ShiftsCalendar / MonthlyEarningsCalendar
 * Matches the actual calendar structure with correct aspect ratio
 */
export function CalendarSkeleton() {
  return (
    <Card className="rounded-card border-0 bg-transparent animate-pulse">
      {/* Calendar header: month picker + year + total */}
      <div className="flex flex-row items-center justify-between py-3">
        <div className="flex items-center gap-1 flex-1">
          {/* Month picker: prev button, month name, next button */}
          <div className="flex items-center gap-2">
            <div className="h-9 w-9 bg-surface-secondary rounded" />
            <div className="h-6 w-24 bg-surface-secondary rounded" />
            <div className="h-9 w-9 bg-surface-secondary rounded" />
          </div>
          {/* Year */}
          <div className="h-5 w-12 bg-surface-secondary rounded ml-1" />
        </div>
        {/* Total earnings */}
        <div className="h-6 w-20 bg-surface-secondary rounded" />
      </div>

      {/* Weekday headers */}
      <div className="grid grid-cols-7 mb-2">
        {Array.from({ length: 7 }, (_, i) => (
          <div key={i} className="text-center py-2">
            <div className="h-3 w-6 bg-surface-secondary rounded mx-auto" />
          </div>
        ))}
      </div>

      {/* Calendar grid - 5 weeks x 7 days */}
      <div className="space-y-1 pb-6">
        {Array.from({ length: 5 }, (_, weekIdx) => (
          <div key={weekIdx} className="grid grid-cols-7 gap-1">
            {Array.from({ length: 7 }, (_, dayIdx) => {
              const cellIdx = weekIdx * 7 + dayIdx;
              const hasShift = cellIdx % 3 === 0;
              const isMonday = dayIdx === 0;

              return (
                <div key={dayIdx} className="aspect-[1/1.25] p-0">
                  <div className="w-full h-full rounded-lg border border-border-subtle bg-surface-primary p-1">
                    <div className="relative flex flex-col w-full h-full">
                      {/* Week number (only on Mondays) */}
                      {isMonday && (
                        <div className="absolute left-0 top-0">
                          <div className="h-2 w-3 bg-surface-secondary rounded" />
                        </div>
                      )}
                      {/* Day number */}
                      <div
                        className="w-full text-right pr-0.5 mb-1"
                        style={{ height: "12px" }}
                      >
                        <div className="h-3 w-3 bg-surface-secondary rounded ml-auto" />
                      </div>
                      {/* Hours placeholder - shows start/end times */}
                      {hasShift && (
                        <div className="flex-1 flex flex-col items-center justify-center">
                          <div className="h-3.5 w-9 bg-surface-secondary rounded" />
                          <div className="h-3.5 w-9 bg-surface-secondary rounded mt-0.5" />
                        </div>
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
      <div className="flex flex-col items-center gap-2 pb-6">
        <div className="flex items-center gap-1 w-full">
          <div className="inline-flex h-11 flex-1 min-w-0 items-center rounded-xl border border-border-subtle bg-surface-secondary/80 p-1 shadow-app-sm dark:shadow-app-inner overflow-hidden">
            <div className="flex h-9 w-full items-center relative">
              {/* Active indicator on left (hours) */}
              <div className="absolute inset-y-0 left-0 w-1/2 rounded-lg bg-white dark:bg-slate-700 shadow-app-md" />
              {/* Hours button (active) */}
              <div className="h-full px-4 flex-1 flex items-center justify-center gap-1.5 relative z-10">
                <div className="h-4 w-8 bg-surface-secondary/50 rounded" />
                <div className="h-4 w-4 bg-surface-secondary/50 rounded" />
              </div>
              {/* Money button (inactive) */}
              <div className="h-full px-4 flex-1 flex items-center justify-center gap-1.5 relative z-10">
                <div className="h-4 w-12 bg-surface-secondary rounded" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </Card>
  );
}
