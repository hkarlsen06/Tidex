import { CalendarSkeleton } from "../CalendarSkeleton";

export function ShiftsSkeleton() {
  return (
    <div className="flex w-full flex-col">
      <div className="flex items-center justify-center min-h-dvh -mx-4 -mt-[calc(3.75rem+env(safe-area-inset-top))] pt-[calc(3.75rem+env(safe-area-inset-top))] pb-[calc(5rem+env(safe-area-inset-bottom))] md:-mt-20 md:pt-20 md:pb-20">
        <div className="w-full px-4">
          <CalendarSkeleton />
        </div>
      </div>
    </div>
  );
}
