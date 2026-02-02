import { Card } from "@/components/app/Card";

/**
 * OnboardingSkeleton - Loading skeleton for the /onboarding page
 * Matches the OnboardingForm layout at step 1 (WageStep)
 */
export function OnboardingSkeleton() {
  return (
    <div className="min-h-full flex justify-center pt-8 pb-32 px-4 bg-background">
      <Card className="w-full max-w-2xl h-fit p-8 shadow-app-lg backdrop-blur-sm border-border bg-surface-secondary">
        {/* Step indicator */}
        <div className="space-y-2 mb-8">
          <div className="flex items-center justify-between">
            <div className="h-4 w-24 bg-surface-primary rounded animate-pulse" />
            <div className="h-4 w-8 bg-surface-primary rounded animate-pulse" />
          </div>
          <div className="h-2 w-full bg-surface-primary rounded-full animate-pulse" />
        </div>

        {/* Content */}
        <div className="space-y-6">
          {/* Title and description */}
          <div className="space-y-2">
            <div className="h-8 w-48 bg-surface-primary rounded animate-pulse" />
            <div className="h-4 w-72 bg-surface-primary rounded animate-pulse" />
          </div>

          {/* Wage type selector (two buttons) */}
          <div className="space-y-6">
            <div className="space-y-2">
              <div className="flex gap-2 sm:gap-4">
                <div className="flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 border-2 border-border bg-surface-primary animate-pulse">
                  <div className="h-8 w-8 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-3 w-16 bg-surface-secondary rounded animate-pulse" />
                </div>
                <div className="flex-1 flex flex-col items-center justify-center gap-2 rounded-2xl px-3 sm:px-8 py-6 border-2 border-text-primary bg-surface-primary">
                  <div className="h-8 w-8 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-3 w-20 bg-surface-secondary rounded animate-pulse" />
                </div>
              </div>
            </div>

            {/* Custom wage inputs (visible by default) */}
            <div className="space-y-4">
              {/* Currency selector */}
              <div className="space-y-2">
                <div className="h-4 w-20 bg-surface-primary rounded animate-pulse" />
                <div className="flex items-stretch gap-2">
                  <div className="flex-1 h-10 bg-surface-primary rounded-md border border-border animate-pulse" />
                  <div className="h-10 w-10 bg-surface-primary rounded-md border border-border animate-pulse" />
                </div>
              </div>

              {/* Hourly wage input */}
              <div className="space-y-2">
                <div className="h-4 w-24 bg-surface-primary rounded animate-pulse opacity-40" />
                <div className="h-10 w-full bg-surface-primary rounded-md border border-border animate-pulse opacity-40" />
              </div>
            </div>
          </div>

          {/* Next button */}
          <div className="h-10 w-full bg-surface-primary rounded-md animate-pulse" />
        </div>
      </Card>
    </div>
  );
}
