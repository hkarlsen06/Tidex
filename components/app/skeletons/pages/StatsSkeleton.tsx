import { Card, CardContent, CardHeader } from "@/components/app/Card";

/**
 * StatsSkeleton - Loading skeleton for the /stats page
 * Matches the actual StatsContent layout with StatsLayoutWrapper
 */
export function StatsSkeleton() {
  return (
    <div className="md:relative md:left-1/2 md:right-1/2 md:-ml-[50vw] md:-mr-[50vw] md:w-screen md:-mx-4">
      <div className="md:mx-auto md:max-w-6xl md:px-6">
        <div
          className="w-full pb-6 pt-2 px-4 flex flex-col space-y-6 md:grid md:auto-rows-max md:gap-6 md:space-y-0"
          style={{
            gridTemplateColumns: "repeat(auto-fit, minmax(min(100%, 400px), 1fr))",
          }}
        >
          {/* Month picker - spans full width on desktop */}
          <div className="flex items-center justify-between mb-2 md:col-span-full">
            <div className="flex items-center gap-1">
              <div className="h-10 w-10 bg-surface-secondary rounded-md animate-pulse" />
              <div className="relative w-24 h-6">
                <div className="h-6 w-full bg-surface-secondary rounded animate-pulse" />
              </div>
              <div className="h-10 w-10 bg-surface-secondary rounded-md animate-pulse" />
            </div>
            <div className="h-5 w-12 bg-surface-secondary rounded animate-pulse mr-3" />
          </div>

          {/* Hero section with key metrics */}
          <div className="space-y-5">
            {/* Hero earnings card */}
            <Card className="border-border bg-surface-primary overflow-hidden">
              <CardContent className="p-6">
                <div className="h-5 w-40 bg-surface-secondary rounded animate-pulse mb-3" />
                <div className="h-12 w-36 bg-surface-secondary rounded animate-pulse" />
                <div className="mt-3 space-y-1">
                  <div className="h-4 w-20 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-3.5 w-32 bg-surface-secondary rounded animate-pulse" />
                </div>
                <div className="flex items-center gap-2 mt-4">
                  <div className="h-5 w-5 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-5 w-44 bg-surface-secondary rounded animate-pulse" />
                </div>
              </CardContent>
            </Card>

            {/* Hours/Shifts grid */}
            <div className="grid grid-cols-2 gap-3">
              <Card className="border-border bg-surface-primary overflow-hidden">
                <CardContent className="p-5">
                  <div className="flex items-start justify-between mb-3">
                    <div className="h-4 w-12 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-5 w-5 bg-surface-secondary rounded animate-pulse opacity-50" />
                  </div>
                  <div className="h-8 w-16 bg-surface-secondary rounded animate-pulse" />
                </CardContent>
              </Card>
              <Card className="border-border bg-surface-primary overflow-hidden">
                <CardContent className="p-5">
                  <div className="flex items-start justify-between mb-3">
                    <div className="h-4 w-10 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-5 w-5 bg-surface-secondary rounded animate-pulse opacity-50" />
                  </div>
                  <div className="h-8 w-8 bg-surface-secondary rounded animate-pulse" />
                </CardContent>
              </Card>
            </div>
          </div>

          {/* Monthly goal progress */}
          <Card className="border-border bg-surface-primary overflow-hidden">
            <CardContent className="p-6">
              <div className="flex items-start justify-between mb-4">
                <div className="h-7 w-28 bg-surface-secondary rounded animate-pulse" />
                <div className="h-5 w-5 bg-surface-secondary rounded animate-pulse opacity-50" />
              </div>
              <div className="grid grid-cols-[1fr,auto] gap-6 items-center">
                <div className="flex flex-col justify-center space-y-3">
                  <div className="h-3.5 w-28 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-2 w-full bg-surface-secondary rounded-full animate-pulse" />
                  <div className="h-4 w-36 bg-surface-secondary rounded animate-pulse" />
                </div>
                <div
                  className="relative shrink-0 bg-surface-secondary rounded-full animate-pulse"
                  style={{ width: 160, height: 160 }}
                />
              </div>
            </CardContent>
          </Card>

          {/* Monthly cumulative comparison chart */}
          <Card className="border-border bg-surface-primary">
            <CardHeader className="pb-3">
              <div className="h-6 w-36 bg-surface-secondary rounded animate-pulse" />
            </CardHeader>
            <CardContent className="px-3 pb-4 pt-1">
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </CardContent>
          </Card>

          {/* Supplement breakdown chart */}
          <Card className="border-border bg-surface-primary">
            <CardHeader className="pb-3">
              <div className="h-6 w-44 bg-surface-secondary rounded animate-pulse" />
            </CardHeader>
            <CardContent className="px-3 pb-4 pt-1">
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </CardContent>
          </Card>

          {/* Weekly earnings chart */}
          <Card className="border-border bg-surface-primary">
            <CardHeader className="pb-3">
              <div className="h-6 w-24 bg-surface-secondary rounded animate-pulse" />
            </CardHeader>
            <CardContent className="px-3 pb-4 pt-1">
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </CardContent>
          </Card>

          {/* Average hourly rate */}
          <Card className="border-border bg-surface-primary overflow-hidden">
            <CardContent className="p-5">
              <div className="flex items-start justify-between mb-3">
                <div className="h-4 w-28 bg-surface-secondary rounded animate-pulse" />
                <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse opacity-50" />
              </div>
              <div className="flex items-baseline gap-1.5">
                <div className="h-8 w-20 bg-surface-secondary rounded animate-pulse" />
                <div className="h-5 w-8 bg-surface-secondary rounded animate-pulse" />
              </div>
            </CardContent>
          </Card>

          {/* Year to date summary header with year picker - spans full width */}
          <div className="flex items-center gap-2 md:col-span-full">
            <div className="h-7 w-20 bg-surface-secondary rounded animate-pulse pl-3" />
            <div className="flex items-center gap-1">
              <div className="h-10 w-10 bg-surface-secondary rounded-md animate-pulse" />
              <div className="relative w-16 h-6">
                <div className="h-6 w-full bg-surface-secondary rounded animate-pulse" />
              </div>
              <div className="h-10 w-10 bg-surface-secondary rounded-md animate-pulse" />
            </div>
          </div>

          {/* Cumulative earnings chart */}
          <Card className="border-border bg-surface-primary">
            <CardHeader className="pb-3">
              <div className="h-6 w-40 bg-surface-secondary rounded animate-pulse" />
            </CardHeader>
            <CardContent className="px-3 pb-4 pt-1">
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </CardContent>
          </Card>

          {/* Last 6 months chart */}
          <Card className="border-border bg-surface-primary">
            <CardHeader className="pb-3">
              <div className="h-6 w-32 bg-surface-secondary rounded animate-pulse" />
            </CardHeader>
            <CardContent className="px-3 pb-4 pt-1">
              <div className="h-64 bg-surface-secondary rounded animate-pulse" />
            </CardContent>
          </Card>

          {/* Employment percentage chart */}
          <Card className="border-border bg-surface-primary overflow-hidden">
            <CardHeader className="pb-3">
              <div className="h-6 w-36 bg-surface-secondary rounded animate-pulse" />
            </CardHeader>
            <CardContent className="p-0">
              <div className="h-64 bg-surface-secondary rounded animate-pulse mx-3 mb-4" />
            </CardContent>
          </Card>

          {/* YTD stat cards */}
          <div className="grid grid-cols-1 gap-3">
            <Card className="border-border bg-surface-primary overflow-hidden">
              <CardContent className="p-5">
                <div className="flex items-start justify-between mb-3">
                  <div className="h-4 w-12 bg-surface-secondary rounded animate-pulse" />
                </div>
                <div className="flex items-baseline gap-1.5">
                  <div className="h-8 w-24 bg-surface-secondary rounded animate-pulse" />
                </div>
              </CardContent>
            </Card>
            <Card className="border-border bg-surface-primary overflow-hidden">
              <CardContent className="p-5">
                <div className="flex items-start justify-between mb-3">
                  <div className="h-4 w-10 bg-surface-secondary rounded animate-pulse" />
                </div>
                <div className="h-8 w-16 bg-surface-secondary rounded animate-pulse" />
              </CardContent>
            </Card>
            <Card className="border-border bg-surface-primary overflow-hidden">
              <CardContent className="p-5">
                <div className="flex items-start justify-between mb-3">
                  <div className="h-4 w-10 bg-surface-secondary rounded animate-pulse" />
                </div>
                <div className="h-8 w-8 bg-surface-secondary rounded animate-pulse" />
              </CardContent>
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}
