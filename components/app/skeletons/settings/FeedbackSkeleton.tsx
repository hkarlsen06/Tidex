import { Card } from "@/components/app/Card";

/**
 * FeedbackSkeleton - Loading skeleton for /settings/feedback
 * Matches: Title + subtitle, FeedbackForm card with textarea and submit button
 *
 * Note: Uses static layout matching SettingsPageWrapper to avoid client component
 * hydration delays in loading.tsx files.
 */
export function FeedbackSkeleton() {
  return (
    <div className="h-full overflow-y-auto pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8">
      <div className="mx-auto max-w-md md:max-w-lg px-4 w-full">
        <div className="py-8">
          <div className="space-y-6">
            {/* Title and subtitle */}
            <div>
              <div className="h-8 w-32 bg-surface-secondary rounded animate-pulse" />
              <div className="h-5 w-72 bg-surface-secondary rounded animate-pulse mt-1" />
            </div>

            {/* FeedbackForm Card */}
            <Card className="p-6">
              <div className="space-y-4">
                {/* Textarea placeholder */}
                <div className="h-[200px] w-full bg-surface-secondary rounded animate-pulse" />

                {/* Character count */}
                <div className="flex justify-end">
                  <div className="h-4 w-20 bg-surface-secondary rounded animate-pulse" />
                </div>

                {/* Submit button */}
                <div className="h-10 w-32 bg-surface-secondary rounded animate-pulse" />
              </div>
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}
