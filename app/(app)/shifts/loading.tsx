import { CalendarSkeleton } from "@/components/app/CalendarSkeleton";
import { ShiftListSkeleton } from "@/components/app/ShiftListSkeleton";

export default function ShiftsLoading() {
  return (
    <div className="flex w-full flex-col">
      {/* Calendar skeleton */}
      <div className="h-[calc(100vh-theme(spacing.24)-theme(spacing.8))] flex items-center justify-center -mt-8">
        <div className="w-full">
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
