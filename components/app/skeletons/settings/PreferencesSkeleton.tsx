import { Card } from "@/components/app/Card";
import { SettingsPageWrapper } from "@/components/app/SettingsPageWrapper";

/**
 * PreferencesSkeleton - Loading skeleton for /settings/preferences
 * Matches: Title + subtitle, PreferencesForm card with toggle switches
 */
export function PreferencesSkeleton() {
  return (
    <SettingsPageWrapper routeKey="settings-preferences">
      <div className="space-y-6">
        {/* Title and subtitle */}
        <div>
          <div className="h-8 w-36 bg-surface-secondary rounded animate-pulse" />
          <div className="h-5 w-64 bg-surface-secondary rounded animate-pulse mt-1" />
        </div>

        {/* PreferencesForm Card */}
        <Card className="p-6">
          <div className="space-y-6">
            <div className="space-y-4">
              {/* Direct time input toggle */}
              <div className="flex items-center justify-between">
                <div className="space-y-0.5 flex-1">
                  <div className="flex items-center gap-2">
                    <div className="h-5 w-40 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-4 w-4 bg-surface-secondary rounded-full animate-pulse" />
                  </div>
                  <div className="h-4 w-72 bg-surface-secondary rounded animate-pulse" />
                </div>
                <div className="h-6 w-11 bg-surface-secondary rounded-full animate-pulse" />
              </div>

              {/* Separator */}
              <div className="h-px bg-border" />

              {/* Full minute range toggle */}
              <div className="flex items-center justify-between">
                <div className="space-y-0.5 flex-1">
                  <div className="flex items-center gap-2">
                    <div className="h-5 w-36 bg-surface-secondary rounded animate-pulse" />
                    <div className="h-4 w-4 bg-surface-secondary rounded-full animate-pulse" />
                  </div>
                  <div className="h-4 w-64 bg-surface-secondary rounded animate-pulse" />
                </div>
                <div className="h-6 w-11 bg-surface-secondary rounded-full animate-pulse" />
              </div>
            </div>
          </div>
        </Card>
      </div>
    </SettingsPageWrapper>
  );
}
