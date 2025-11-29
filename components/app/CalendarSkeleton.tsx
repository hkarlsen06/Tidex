import { Card } from "@/components/app/Card";

export function CalendarSkeleton() {
  // Create 35 day cells (5 weeks x 7 days)
  const dayCells = Array.from({ length: 35 }, (_, i) => i);

  return (
    <Card className="rounded-card border-0 bg-transparent animate-pulse">
      <div className="flex flex-row items-center justify-between py-3">
        <div className="flex items-center gap-1 flex-1">
          {/* Month picker skeleton */}
          <div className="flex items-center gap-2">
            {/* Previous button */}
            <div className="h-9 w-9 bg-surface-secondary rounded" />
            {/* Month name */}
            <div className="h-6 w-24 bg-surface-secondary rounded" />
            {/* Next button */}
            <div className="h-9 w-9 bg-surface-secondary rounded" />
          </div>
          {/* Year */}
          <div className="h-5 w-12 bg-surface-secondary rounded ml-1" />
        </div>
        {/* Total earnings */}
        <div className="h-6 w-24 bg-surface-secondary rounded" />
      </div>

      {/* Weekday headers */}
      <div className="grid grid-cols-7 mb-2">
        {Array.from({ length: 7 }, (_, i) => (
          <div key={i} className="text-center py-2">
            <div className="h-3 w-8 bg-surface-secondary rounded mx-auto" />
          </div>
        ))}
      </div>

      {/* Calendar grid */}
      <div className="space-y-1 pb-6">
        {Array.from({ length: 5 }, (_, weekIdx) => (
          <div key={weekIdx} className="grid grid-cols-7 gap-1">
            {dayCells.slice(weekIdx * 7, (weekIdx + 1) * 7).map((dayIdx) => (
              <div
                key={dayIdx}
                className="aspect-square p-0"
              >
                <div className="w-full h-full rounded-lg border border-border-subtle bg-surface-primary p-1 pb-1.5">
                  <div className="relative flex flex-col items-center justify-start gap-0.5 w-full h-full">
                    {/* Day number */}
                    <div className="w-full text-right pr-1">
                      <div className="h-3 w-4 bg-surface-secondary rounded ml-auto" />
                    </div>
                    {/* Earnings/hours placeholder */}
                    {dayIdx % 3 === 0 && (
                      <div className="h-3 w-12 bg-surface-secondary rounded mt-1" />
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        ))}
      </div>

      {/* Toggle buttons for earnings/hours view */}
      <div className="flex justify-center pb-6">
        <div className="inline-flex items-center gap-1 rounded-full border border-border-subtle bg-surface-secondary/80 p-1 w-2/3">
          {/* Left button (earnings) */}
          <div className="h-9 flex-1 bg-surface-secondary rounded-full" />
          {/* Right button (hours) */}
          <div className="h-9 flex-1 bg-surface-secondary rounded-full" />
        </div>
      </div>
    </Card>
  );
}
