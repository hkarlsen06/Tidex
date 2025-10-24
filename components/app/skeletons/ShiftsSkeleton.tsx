import { CalendarSkeleton } from "../CalendarSkeleton";

export function ShiftsSkeleton() {
  return (
    <div className="flex w-full flex-col">
      <div className="h-[calc(100vh-theme(spacing.24)-theme(spacing.8))] flex items-center justify-center -mt-8">
        <div className="w-full">
          <CalendarSkeleton />
        </div>
      </div>
    </div>
  );
}
