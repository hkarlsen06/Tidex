import { CalendarSkeleton } from "../CalendarSkeleton";

export function ShiftsSkeleton() {
  return (
    <div className="flex w-full flex-col lg:relative lg:left-1/2 lg:right-1/2 lg:-ml-[50vw] lg:-mr-[50vw] lg:w-screen lg:flex-row lg:gap-0 lg:px-0 lg:items-start lg:pt-6">
      {/* Calendar Section - matches ShiftsView structure */}
      <div className="min-h-full flex flex-col justify-center px-4 lg:min-h-0 lg:w-1/2 lg:shrink-0 lg:sticky lg:top-6 lg:justify-start lg:items-center lg:px-0">
        <div className="w-full max-w-md md:max-w-lg lg:max-w-none lg:w-[480px]">
          <CalendarSkeleton />
        </div>
      </div>
    </div>
  );
}
