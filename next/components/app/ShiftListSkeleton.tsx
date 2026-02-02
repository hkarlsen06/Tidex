import { Card, CardHeader } from "@/components/app/Card";
import { ShiftCardSkeleton } from "./ShiftCardSkeleton";

export function ShiftListSkeleton() {
  return (
    <div className="flex flex-col gap-8">
      {/* Week 1 */}
      <section className="space-y-4">
        <Card className="rounded-card border-0">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 py-3">
            <div className="flex items-center gap-2">
              <div className="h-5 w-16 bg-surface-secondary rounded animate-pulse" />
              <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse" />
            </div>
            <div className="h-5 w-24 bg-surface-secondary rounded animate-pulse" />
          </CardHeader>
        </Card>
        <div className="space-y-4">
          <ShiftCardSkeleton />
          <ShiftCardSkeleton />
          <ShiftCardSkeleton />
        </div>
      </section>

      {/* Week 2 */}
      <section className="space-y-4">
        <Card className="rounded-card border-0">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 py-3">
            <div className="flex items-center gap-2">
              <div className="h-5 w-16 bg-surface-secondary rounded animate-pulse" />
              <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse" />
            </div>
            <div className="h-5 w-24 bg-surface-secondary rounded animate-pulse" />
          </CardHeader>
        </Card>
        <div className="space-y-4">
          <ShiftCardSkeleton />
          <ShiftCardSkeleton />
        </div>
      </section>
    </div>
  );
}
