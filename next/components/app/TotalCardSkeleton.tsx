import { Card, CardHeader, CardContent } from "@/components/app/Card";

export function TotalCardSkeleton() {
  return (
    <Card className="rounded-3xl">
      <CardHeader className="pb-3">
        <div className="h-4 w-32 bg-surface-secondary rounded animate-pulse" />
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-baseline gap-2">
          <div className="h-12 w-40 bg-surface-secondary rounded animate-pulse" />
          <div className="h-6 w-16 bg-surface-secondary rounded animate-pulse" />
        </div>
        <div className="space-y-2">
          <div className="flex justify-between items-center">
            <div className="h-4 w-24 bg-surface-secondary rounded animate-pulse" />
            <div className="h-4 w-20 bg-surface-secondary rounded animate-pulse" />
          </div>
          <div className="flex justify-between items-center">
            <div className="h-4 w-28 bg-surface-secondary rounded animate-pulse" />
            <div className="h-4 w-20 bg-surface-secondary rounded animate-pulse" />
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
