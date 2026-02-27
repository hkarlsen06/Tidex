"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import dynamic from "next/dynamic";
import { ArrowLeft } from "lucide-react";
import { SharingPageSkeleton } from "@/components/app/skeletons";
import { ManageSharingModal } from "./ManageSharingModal";
import { CurrencyProvider } from "@/components/providers/CurrencyProvider";
import { useTranslations } from "@/lib/i18n/client";
import { useSharingViewState } from "@/lib/hooks/useSharingViewState";
import type {
  SharedUser,
  Friend,
} from "@/data-access/sharing";
import type {
  ShiftWithComputations,
  UserSettings,
  SupplementRule,
  WageSnapshot,
  Job,
} from "@/lib/payroll";
import type { PayoutTaxSettings } from "@/data-access/shifts";

// Dynamically import ShiftsView to avoid Turbopack HMR issues with server action imports
// ShiftsView imports server actions (deleteShift, updateShift, etc.) that cause HMR errors
// in development when bundled in contexts where they're not used (readOnly mode)
const ShiftsView = dynamic(
  () =>
    import("@/components/shifts/ShiftsView").then((mod) => ({
      default: mod.ShiftsView,
    })),
  { ssr: false, loading: () => <SharingPageSkeleton /> },
);

type SharingPageContentProps = {
  friends: Friend[];
  shareCapacity: { canAdd: boolean; currentCount: number; limit: number };
  selectedOwnerId: string;
  selectedSharer: SharedUser;
  sharedShifts: ShiftWithComputations[];
  /** Sharer's settings - includes currency for display */
  sharedSettings: UserSettings & { currency?: string | null };
  presetRules: SupplementRule[];
  /** Whether the owner allows this viewer to see earnings data */
  showEarnings: boolean;
  /** Owner jobs used to render job badges/context in shared shifts */
  jobs: Job[];
  /** Payout month tax settings for calculating after-tax monthly totals */
  payoutTaxSettings?: PayoutTaxSettings;
  /** Owner's wage snapshots for computing payoutTaxSettings per month */
  wageSnapshots?: WageSnapshot[];
  /** Deep link: dates to highlight in calendar (from push notification) */
  highlightDates?: Set<string> | null;
  /** User-specific cache key for browser HTTP cache isolation */
  cacheKey: string;
};

/**
 * Detail view for viewing a specific sharer's shifts.
 *
 * Now uses the global MonthContext (same as /shifts and dashboard) so month
 * navigation stays in sync across all routes. The cacheComponents stale state
 * issues are handled by:
 * - ShiftsView using useRef for loaded months tracking
 * - Reference equality checks to detect actual SSR changes vs reveals
 * - Keys on controlled components (MonthPicker, DayPicker)
 *
 * See docs/cacheComponents-stale-state-bug.md for details.
 */
export function SharingPageContent({
  friends,
  shareCapacity,
  selectedOwnerId,
  selectedSharer,
  sharedShifts,
  sharedSettings,
  presetRules,
  showEarnings,
  jobs,
  payoutTaxSettings,
  wageSnapshots,
  highlightDates,
  cacheKey,
}: SharingPageContentProps) {
  const { t, locale } = useTranslations();
  const router = useRouter();
  const [manageSharingOpen, setManageSharingOpen] = useState(false);
  const { saveViewState } = useSharingViewState();

  const sharingPath = `/${locale}/sharing`;

  // Save the current sharer to localStorage whenever viewing their shifts
  useEffect(() => {
    if (selectedOwnerId) {
      saveViewState(selectedOwnerId);
    }
  }, [selectedOwnerId, saveViewState]);

  const handleBack = () => {
    saveViewState(null); // Clear saved state when returning to list
    router.push(sharingPath);
  };

  // Use the sharer's currency for displaying their shifts
  const sharerCurrency = sharedSettings.currency ?? "kr";

  return (
    <CurrencyProvider currency={sharerCurrency}>
      <ShiftsView
        shifts={sharedShifts}
        defaultView="calendar"
        userSettings={sharedSettings}
        presetRules={presetRules}
        jobs={jobs}
        readOnly={true}
        sharedOwnerId={selectedOwnerId}
        ownerName={selectedSharer.firstName ?? selectedSharer.email ?? "Bruker"}
        showEarnings={showEarnings}
        payoutTaxSettings={payoutTaxSettings}
        wageSnapshots={wageSnapshots}
        highlightDates={highlightDates}
        cacheKey={cacheKey}
        headerSlot={
          <div className="flex items-center justify-between">
            <button
              type="button"
              onClick={handleBack}
              className="inline-flex items-center gap-2 text-sm text-text-secondary hover:text-text-primary transition-colors"
            >
              <ArrowLeft className="h-4 w-4" />
              <span>{t.common.back}</span>
            </button>
            <span className="text-sm font-medium text-text-primary">
              {selectedSharer.firstName ?? selectedSharer.email?.split("@")[0] ?? "Bruker"}
            </span>
          </div>
        }
      />
      <ManageSharingModal
        isOpen={manageSharingOpen}
        onCloseAction={() => setManageSharingOpen(false)}
        friends={friends}
        shareCapacity={shareCapacity}
      />
    </CurrencyProvider>
  );
}
