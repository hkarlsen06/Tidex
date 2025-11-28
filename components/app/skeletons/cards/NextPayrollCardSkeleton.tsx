import { Card, CardHeader } from "@/components/app/Card";

/**
 * Skeleton for NextPayrollCard
 * Matches the actual card structure: date/label on left, amount/breakdown on right
 */
export function NextPayrollCardSkeleton() {
  return (
    <Card className="bg-surface-primary rounded-3xl">
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-6">
        <div className="space-y-1">
          {/* Date (e.g., "15. januar") */}
          <div className="h-7 w-28 bg-surface-secondary rounded animate-pulse" />
          {/* Calendar icon + payroll label */}
          <div className="flex items-center gap-1">
            <div className="h-4 w-4 bg-surface-secondary rounded animate-pulse" />
            <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse" />
          </div>
        </div>
        <div className="text-right space-y-1">
          {/* Amount (e.g., "12 500 kr") */}
          <div className="h-8 w-24 bg-surface-secondary rounded animate-pulse" />
          {/* Breakdown (e.g., "15 000 - 2 500") */}
          <div className="h-3 w-20 bg-surface-secondary rounded animate-pulse ml-auto" />
        </div>
      </CardHeader>
    </Card>
  );
}
