export default function StatsLoading() {
  return (
    <div className="md:relative md:left-1/2 md:right-1/2 md:-ml-[50vw] md:-mr-[50vw] md:w-screen md:-mx-4">
      <div className="md:mx-auto md:max-w-6xl md:px-6">
        <div className="flex flex-col w-full pb-6 pt-2 space-y-6 md:grid md:auto-rows-max md:gap-6 md:space-y-0" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 400px), 1fr))' }}>

          {/* Month picker skeleton - spans full width on desktop */}
          <div className="flex items-center justify-between mb-2 md:col-span-full">
            <div className="flex items-center gap-3">
              <div className="h-8 w-8 bg-surface-secondary rounded-full animate-pulse" />
              <div className="h-6 w-24 bg-surface-secondary rounded animate-pulse" />
              <div className="h-8 w-8 bg-surface-secondary rounded-full animate-pulse" />
            </div>
            {/* Year skeleton */}
            <div className="h-6 w-16 bg-surface-secondary rounded animate-pulse mr-3" />
          </div>

          {/* Hero section with key metrics */}
          <div className="space-y-5">
            {/* Hero earnings card skeleton */}
            <div className="rounded-3xl border border-border bg-surface-primary overflow-hidden">
              <div className="p-6">
                <div className="h-5 w-48 bg-surface-secondary rounded animate-pulse mb-3" />
                <div className="flex items-baseline gap-2 mb-3">
                  <div className="h-12 w-32 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-7 w-8 bg-surface-secondary rounded animate-pulse" />
                </div>
                <div className="space-y-1">
                  <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-3 w-40 bg-surface-secondary rounded animate-pulse" />
                </div>
                <div className="flex items-center gap-2 mt-4">
                  <div className="h-5 w-5 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-5 w-36 bg-surface-secondary rounded animate-pulse" />
                </div>
              </div>
            </div>

            {/* Hours and Shifts grid */}
            <div className="grid grid-cols-2 gap-3">
              <div className="rounded-3xl border border-border bg-surface-primary overflow-hidden">
                <div className="p-5">
                  <div className="flex items-start justify-between mb-3">
                    <div className="h-4 w-16 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-5 w-5 bg-surface-secondary rounded animate-pulse opacity-50" />
                  </div>
                  <div className="h-8 w-20 bg-surface-secondary rounded animate-pulse" />
                </div>
              </div>
              <div className="rounded-3xl border border-border bg-surface-primary overflow-hidden">
                <div className="p-5">
                  <div className="flex items-start justify-between mb-3">
                    <div className="h-4 w-16 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-5 w-5 bg-surface-secondary rounded animate-pulse opacity-50" />
                  </div>
                  <div className="h-8 w-16 bg-surface-secondary rounded animate-pulse" />
                </div>
              </div>
            </div>
          </div>

          {/* Monthly goal progress placeholder */}
          <div className="rounded-3xl border border-border bg-surface-primary overflow-hidden">
            <div className="p-5">
              <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse mb-3" />
              <div className="h-2 w-full bg-surface-secondary rounded-full animate-pulse" />
            </div>
          </div>

          {/* Monthly cumulative comparison chart */}
          <div className="rounded-3xl border border-border bg-surface-primary">
            <div className="flex flex-col space-y-1.5 p-6 pb-3">
              <div className="h-6 w-40 bg-surface-secondary rounded animate-pulse" />
            </div>
            <div className="p-6 px-3 pb-4 pt-1">
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </div>
          </div>

          {/* Supplement breakdown chart */}
          <div className="rounded-3xl border border-border bg-surface-primary">
            <div className="flex flex-col space-y-1.5 p-6 pb-3">
              <div className="h-6 w-40 bg-surface-secondary rounded animate-pulse" />
            </div>
            <div className="p-6 px-3 pb-4 pt-1">
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </div>
          </div>

          {/* Weekly earnings chart */}
          <div className="rounded-3xl border border-border bg-surface-primary">
            <div className="flex flex-col space-y-1.5 p-6 pb-3">
              <div className="h-6 w-32 bg-surface-secondary rounded animate-pulse" />
            </div>
            <div className="p-6 px-3 pb-4 pt-1">
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </div>
          </div>

          {/* Average rate card */}
          <div className="rounded-3xl border border-border bg-surface-primary overflow-hidden">
            <div className="p-5">
              <div className="flex items-start justify-between mb-3">
                <div className="h-4 w-28 bg-surface-secondary rounded animate-pulse" />
                <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse opacity-50" />
              </div>
              <div className="flex items-baseline gap-1.5">
                <div className="h-8 w-20 bg-surface-secondary rounded animate-pulse" />
                <div className="h-6 w-12 bg-surface-secondary rounded animate-pulse" />
              </div>
            </div>
          </div>

          {/* Year to date summary header - spans full width on desktop */}
          <div className="h-7 w-32 bg-surface-secondary rounded animate-pulse pl-6 md:col-span-full" />

          {/* Cumulative earnings chart */}
          <div className="rounded-3xl border border-border bg-surface-primary">
            <div className="flex flex-col space-y-1.5 p-6 pb-3">
              <div className="h-6 w-44 bg-surface-secondary rounded animate-pulse" />
            </div>
            <div className="p-6 px-3 pb-4 pt-1">
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </div>
          </div>

          {/* Last 6 months chart */}
          <div className="rounded-3xl border border-border bg-surface-primary">
            <div className="flex flex-col space-y-1.5 p-6 pb-3">
              <div className="h-6 w-36 bg-surface-secondary rounded animate-pulse" />
            </div>
            <div className="p-6 px-3 pb-4 pt-1">
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </div>
          </div>

          {/* Day of week breakdown */}
          <div className="rounded-3xl border border-border bg-surface-primary">
            <div className="flex flex-col space-y-1.5 p-6 pb-3">
              <div className="h-6 w-52 bg-surface-secondary rounded animate-pulse" />
            </div>
            <div className="p-6 px-3 pb-4 pt-1">
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </div>
          </div>

          {/* YTD stats grid - grouped together in one grid cell with internal grid */}
          <div className="grid grid-cols-1 gap-3">
            <div className="rounded-3xl border border-border bg-surface-primary overflow-hidden">
              <div className="p-5">
                <div className="h-4 w-16 bg-surface-secondary rounded animate-pulse mb-3" />
                <div className="flex items-baseline gap-1.5">
                  <div className="h-8 w-24 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-6 w-8 bg-surface-secondary rounded animate-pulse" />
                </div>
              </div>
            </div>
            <div className="rounded-3xl border border-border bg-surface-primary overflow-hidden">
              <div className="p-5">
                <div className="h-4 w-16 bg-surface-secondary rounded animate-pulse mb-3" />
                <div className="h-8 w-20 bg-surface-secondary rounded animate-pulse" />
              </div>
            </div>
            <div className="rounded-3xl border border-border bg-surface-primary overflow-hidden">
              <div className="p-5">
                <div className="h-4 w-16 bg-surface-secondary rounded animate-pulse mb-3" />
                <div className="h-8 w-16 bg-surface-secondary rounded animate-pulse" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
