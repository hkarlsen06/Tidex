import { CalendarSkeleton } from "@/components/app/CalendarSkeleton";
import { ShiftListSkeleton } from "@/components/app/ShiftListSkeleton";

export default function ShiftsLoading() {
  return (
    <div className="flex w-full flex-col">
      {/* Calendar skeleton */}
      <div className="flex items-center justify-center min-h-[calc(100dvh-3.75rem-env(safe-area-inset-top))] -mx-4 pb-[calc(5rem+env(safe-area-inset-bottom))] md:min-h-[calc(100dvh-5rem)] md:pb-20">
        <div className="w-full px-4">
          <CalendarSkeleton />
        </div>
      </div>

      {/* Shifts list skeleton */}
      <div className="pb-10">
        <ShiftListSkeleton />
      </div>
    </div>
  );
}
