import { Card, CardContent } from "@/components/app/Card";

/**
 * Skeleton for TotalCard
 * Matches the actual card structure: centered percentage, large amount, subtitle
 */
export function TotalCardSkeleton() {
  return (
    <Card className="bg-surface-primary rounded-3xl">
      <CardContent className="py-6">
        <div className="text-center">
          {/* Percentage change indicator */}
          <div className="flex items-center justify-center gap-2">
            <div className="h-6 w-6 bg-surface-secondary rounded animate-pulse" />
            <div className="h-6 w-12 bg-surface-secondary rounded animate-pulse" />
          </div>
          {/* Large total amount */}
          <div className="mt-3">
            <div className="h-16 w-48 bg-surface-secondary rounded mx-auto animate-pulse" />
          </div>
          {/* Subtitle (projected total or gross before tax) */}
          <div className="mt-4">
            <div className="h-5 w-40 bg-surface-secondary rounded mx-auto animate-pulse" />
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
