import { CalendarSkeleton } from "../CalendarSkeleton";

export function ShiftsSkeleton() {
  return (
    <div className="mx-auto max-w-[800px] space-y-6">
      {/* View toggle skeleton */}
      <div className="flex justify-center">
        <div className="inline-flex items-center gap-1 rounded-full border border-border-subtle bg-surface-secondary/80 p-1 w-64 h-12 animate-pulse" />
      </div>

      {/* Calendar skeleton (default view) */}
      <CalendarSkeleton />
    </div>
  );
}
