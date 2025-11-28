import { AddCalendarSkeleton } from "@/components/app/skeletons";

export default function AddShiftLoading() {
  return (
    <div className="mx-auto flex w-full max-w-4xl flex-col gap-6 pt-8 pb-24">
      {/* Header skeleton */}
      <div className="flex flex-col gap-4 animate-pulse">
        <div className="space-y-1">
          <div className="h-3 w-20 bg-surface-secondary rounded" />
          <div className="flex items-center justify-between gap-3">
            <div className="h-8 w-40 bg-surface-secondary rounded" />
            <div className="inline-flex items-center gap-1 rounded-full border border-border-subtle bg-surface-secondary/80 p-1 shadow-app-sm dark:shadow-app-inner shrink-0">
              <div className="h-9 w-20 bg-surface-secondary rounded-full" />
              <div className="h-9 w-20 bg-surface-secondary/50 rounded-full" />
            </div>
          </div>
        </div>
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div className="h-4 w-64 bg-surface-secondary rounded" />
        </div>
      </div>

      {/* Loading skeletons for the interactive parts */}
      <div className="space-y-6">
        {/* Month picker and year skeleton */}
        <div className="flex flex-wrap items-center justify-between gap-4 animate-pulse">
          <div className="flex items-center gap-2">
            <div className="h-9 w-9 bg-surface-secondary rounded" />
            <div className="h-6 w-24 bg-surface-secondary rounded" />
            <div className="h-9 w-9 bg-surface-secondary rounded" />
          </div>
          <div className="h-6 w-16 bg-surface-secondary rounded-full px-3 py-1" />
        </div>

        {/* Calendar skeleton */}
        <AddCalendarSkeleton />

        {/* Time inputs skeleton */}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 animate-pulse">
          <div className="min-w-0 space-y-3 rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 shadow-app-inner">
            <div className="h-3 w-12 bg-surface-secondary rounded" />
            <div className="flex min-w-0 items-center gap-2">
              <div className="h-10 flex-1 bg-surface-secondary rounded" />
              <div className="h-10 w-10 bg-surface-secondary rounded-xl" />
            </div>
          </div>
          <div className="min-w-0 space-y-3 rounded-2xl border border-border-subtle bg-surface-secondary/70 p-4 shadow-app-inner">
            <div className="h-3 w-12 bg-surface-secondary rounded" />
            <div className="flex min-w-0 items-center gap-2">
              <div className="h-10 flex-1 bg-surface-secondary rounded" />
              <div className="h-10 w-10 bg-surface-secondary rounded-xl" />
            </div>
          </div>
        </div>

        {/* Selected dates summary skeleton */}
        <div className="rounded-2xl border border-border-subtle bg-surface-secondary/70 px-4 py-3 shadow-app-inner animate-pulse">
          <div className="h-4 w-64 bg-surface-secondary rounded" />
        </div>

        {/* Submit button skeleton */}
        <div className="flex justify-center animate-pulse">
          <div className="h-12 w-40 bg-surface-secondary rounded-2xl" />
        </div>
      </div>
    </div>
  );
}
