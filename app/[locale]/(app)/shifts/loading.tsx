import { CalendarSkeleton } from "@/components/app/CalendarSkeleton";
import { ShiftListSkeleton } from "@/components/app/ShiftListSkeleton";

export default function ShiftsLoading() {
  return (
    <div className="flex w-full flex-col lg:relative lg:left-1/2 lg:right-1/2 lg:-ml-[50vw] lg:-mr-[50vw] lg:w-screen lg:flex-row lg:gap-0 lg:px-0 lg:items-start lg:pt-6">
      {/* Calendar Section - Left half of screen, centered within */}
      <div className="flex items-center justify-center min-h-[calc(100dvh-3.75rem-env(safe-area-inset-top))] -mx-4 pb-[calc(5rem+env(safe-area-inset-bottom))] md:min-h-[calc(100dvh-5rem)] md:pb-20 lg:min-h-0 lg:pb-0 lg:mx-0 lg:w-1/2 lg:shrink-0 lg:sticky lg:top-6 lg:justify-center">
        <div className="w-full px-4 lg:px-0 lg:w-[480px]">
          <CalendarSkeleton />
        </div>
      </div>

      {/* Shifts List Section - Right half of screen, centered within */}
      <div className="lg:w-1/2 lg:flex lg:justify-center">
        <div className="pb-10 lg:w-full lg:max-w-[512px] lg:overflow-y-auto lg:max-h-[calc(100vh-8rem)] lg:px-4">
          <ShiftListSkeleton />
        </div>
      </div>
    </div>
  );
}
