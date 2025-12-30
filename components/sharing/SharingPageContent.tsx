"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import dynamic from "next/dynamic";
import { ArrowLeft } from "lucide-react";
import { SharingPageSkeleton } from "@/components/app/skeletons";
import { ManageSharingModal } from "./ManageSharingModal";
import { SharingDropdown } from "./SharingDropdown";
import { SharingMonthProvider, useSharingMonth } from "./SharingMonthContext";
import { useTranslations } from "@/lib/i18n/client";
import { useSharingViewState } from "@/lib/hooks/useSharingViewState";
import type {
  SharedUser,
  Friend,
  SharedShiftsAggregates,
} from "@/data-access/sharing";
import type {
  ShiftWithComputations,
  UserSettings,
  SupplementRule,
} from "@/lib/payroll";

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
  sharers: SharedUser[];
  friends: Friend[];
  shareCapacity: { canAdd: boolean; currentCount: number; limit: number };
  selectedOwnerId: string;
  selectedSharer: SharedUser;
  sharedShifts: ShiftWithComputations[];
  sharedSettings: UserSettings;
  sharedAggregates: SharedShiftsAggregates | null;
  presetRules: SupplementRule[];
  /** Whether the owner allows this viewer to see earnings data */
  showEarnings: boolean;
  /** Deep link: dates to highlight in calendar (from push notification) */
  highlightDates?: Set<string> | null;
};

/**
 * Inner component that uses the isolated SharingMonthContext.
 * Must be rendered inside SharingMonthProvider.
 */
function SharingPageContentInner({
  sharers,
  friends,
  shareCapacity,
  selectedOwnerId,
  selectedSharer,
  sharedShifts,
  sharedSettings,
  presetRules,
  showEarnings,
  highlightDates,
}: SharingPageContentProps) {
  const { t, locale } = useTranslations();
  const router = useRouter();
  const [manageSharingOpen, setManageSharingOpen] = useState(false);
  const { saveViewState } = useSharingViewState();

  // Use isolated month context for sharing page
  const sharingMonthContext = useSharingMonth();

  const sharingPath = `/${locale}/sharing`;

  // Save the current sharer to localStorage whenever viewing their shifts
  useEffect(() => {
    if (selectedOwnerId) {
      saveViewState(selectedOwnerId);
    }
  }, [selectedOwnerId, saveViewState]);

  const handleSharerSelect = (sharerId: string | null) => {
    if (sharerId) {
      router.push(`/${locale}/sharing?view=${sharerId}`);
    } else {
      router.push(sharingPath);
    }
  };

  const handleBack = () => {
    saveViewState(null); // Clear saved state when returning to list
    router.push(sharingPath);
  };

  return (
    <>
      <ShiftsView
        shifts={sharedShifts}
        defaultView="calendar"
        userSettings={sharedSettings}
        presetRules={presetRules}
        readOnly={true}
        sharedOwnerId={selectedOwnerId}
        ownerName={selectedSharer.firstName ?? selectedSharer.email ?? "Bruker"}
        showEarnings={showEarnings}
        monthContext={sharingMonthContext}
        highlightDates={highlightDates}
        headerSlot={
          <div className="flex flex-col gap-3">
            <button
              type="button"
              onClick={handleBack}
              className="inline-flex items-center gap-2 text-sm text-text-secondary hover:text-text-primary transition-colors w-fit"
            >
              <ArrowLeft className="h-4 w-4" />
              <span>{t.common.back}</span>
            </button>
            <SharingDropdown
              sharers={sharers}
              selectedId={selectedOwnerId}
              onSelect={handleSharerSelect}
            />
          </div>
        }
      />
      <ManageSharingModal
        isOpen={manageSharingOpen}
        onCloseAction={() => setManageSharingOpen(false)}
        friends={friends}
        shareCapacity={shareCapacity}
      />
    </>
  );
}

/**
 * Detail view for viewing a specific sharer's shifts.
 * Wrapped in SharingMonthProvider to isolate month state from the global MonthProvider,
 * preventing AnimatePresence conflicts when navigating between /shifts and /sharing.
 */
export function SharingPageContent(props: SharingPageContentProps) {
  return (
    <SharingMonthProvider>
      <SharingPageContentInner {...props} />
    </SharingMonthProvider>
  );
}
