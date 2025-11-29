import { Card, CardHeader } from "@/components/app/Card";

export function NextPayrollCardSkeleton() {
  return (
    <Card className="rounded-3xl">
      <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0 py-6">
        <div className="space-y-1 flex-1">
          <div className="h-7 w-40 bg-surface-secondary rounded-md animate-pulse" />
          <div className="flex items-center gap-3">
            <div className="h-4 w-28 bg-surface-secondary rounded animate-pulse" />
          </div>
        </div>
        <div className="text-right space-y-1">
          <div className="h-8 w-24 bg-surface-secondary rounded-md animate-pulse" />
          <div className="h-3 w-20 bg-surface-secondary rounded animate-pulse ml-auto" />
        </div>
      </CardHeader>
    </Card>
  );
}
