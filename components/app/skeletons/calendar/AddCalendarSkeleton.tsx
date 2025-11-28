import { Card } from "@/components/app/Card";

/**
 * Skeleton for the calendar in the /shifts/add route.
 * Simplified version without the month picker header or earnings/hours toggle.
 */
export function AddCalendarSkeleton() {
  return (
    <Card className="rounded-card border-0 animate-pulse">
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
                      {/* Placeholder for some days to show variation */}
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
    </Card>
  );
}
