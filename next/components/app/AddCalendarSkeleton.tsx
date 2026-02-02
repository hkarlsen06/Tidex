import { Card } from "@/components/app/Card";

/**
 * Skeleton loader for the calendar in the /shifts/add route.
 * Simplified version without the earnings/hours toggle that exists in the main shifts view.
 */
export function AddCalendarSkeleton() {
  // Create 35 day cells (5 weeks x 7 days)
  const dayCells = Array.from({ length: 35 }, (_, i) => i);

  return (
    <Card className="rounded-card border-0 animate-pulse">
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
                    {/* Placeholder for some days to show variation */}
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
    </Card>
  );
}
