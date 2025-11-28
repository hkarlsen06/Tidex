import { Card } from "@/components/app/Card";
import { SettingsPageWrapper } from "@/components/app/SettingsPageWrapper";

/**
 * SecuritySkeleton - Loading skeleton for /settings/security
 * Matches: Title + subtitle, PasswordCard, Connected accounts section (Phone + Google cards), MFA section
 */
export function SecuritySkeleton() {
  return (
    <SettingsPageWrapper routeKey="settings-security">
      <div className="space-y-6">
        {/* Title and subtitle */}
        <div>
          <div className="h-8 w-24 bg-surface-secondary rounded animate-pulse" />
          <div className="h-5 w-72 bg-surface-secondary rounded animate-pulse mt-1" />
        </div>

        {/* PasswordCard */}
        <Card className="p-6">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
            <div className="flex items-center gap-4 flex-1 min-w-0">
              {/* Lock icon box */}
              <div className="p-3 rounded-lg bg-surface-secondary shrink-0">
                <div className="h-6 w-6 bg-surface-primary rounded animate-pulse" />
              </div>
              <div className="flex-1 min-w-0">
                <div className="h-5 w-20 bg-surface-secondary rounded animate-pulse" />
                <div className="h-4 w-48 bg-surface-secondary rounded animate-pulse mt-0.5" />
              </div>
            </div>
            <div className="h-10 w-full sm:w-28 bg-surface-secondary rounded-md animate-pulse" />
          </div>
        </Card>

        {/* Connected accounts section */}
        <div className="space-y-4 pt-4">
          <div className="border-t border-border pt-4">
            <div className="h-6 w-40 bg-surface-secondary rounded animate-pulse mb-1" />
            <div className="h-4 w-64 bg-surface-secondary rounded animate-pulse mb-4" />
          </div>

          {/* PhoneConnectionCard */}
          <Card className="p-6">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
              <div className="flex items-center gap-4 flex-1 min-w-0">
                <div className="p-3 rounded-lg bg-surface-secondary shrink-0">
                  <div className="h-6 w-6 bg-surface-primary rounded animate-pulse" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="h-5 w-24 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-4 w-36 bg-surface-secondary rounded animate-pulse mt-0.5" />
                </div>
              </div>
              <div className="h-10 w-full sm:w-24 bg-surface-secondary rounded-md animate-pulse" />
            </div>
          </Card>

          {/* GoogleConnectionCard */}
          <Card className="p-6">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
              <div className="flex items-center gap-4 flex-1 min-w-0">
                <div className="p-3 rounded-lg bg-surface-secondary shrink-0">
                  <div className="h-6 w-6 bg-surface-primary rounded animate-pulse" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="h-5 w-20 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-4 w-32 bg-surface-secondary rounded animate-pulse mt-0.5" />
                </div>
              </div>
              <div className="h-10 w-full sm:w-24 bg-surface-secondary rounded-md animate-pulse" />
            </div>
          </Card>
        </div>

        {/* MFA section */}
        <div className="space-y-4 pt-4">
          <div className="border-t border-border pt-4">
            <div className="h-6 w-48 bg-surface-secondary rounded animate-pulse mb-1" />
            <div className="h-4 w-80 bg-surface-secondary rounded animate-pulse mb-4" />
          </div>

          {/* MFA Card placeholder */}
          <Card className="p-6">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
              <div className="flex items-center gap-4 flex-1 min-w-0">
                <div className="p-3 rounded-lg bg-surface-secondary shrink-0">
                  <div className="h-6 w-6 bg-surface-primary rounded animate-pulse" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="h-5 w-36 bg-surface-secondary rounded animate-pulse" />
                  <div className="h-4 w-52 bg-surface-secondary rounded animate-pulse mt-0.5" />
                </div>
              </div>
              <div className="h-10 w-full sm:w-24 bg-surface-secondary rounded-md animate-pulse" />
            </div>
          </Card>
        </div>
      </div>
    </SettingsPageWrapper>
  );
}
