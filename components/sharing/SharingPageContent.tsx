"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Settings, Users } from "lucide-react";
import { Button } from "@/components/app/Button";
import { Card, CardHeader, CardTitle, CardDescription } from "@/components/app/Card";
import { ScrollablePageWrapper } from "@/components/app/ScrollablePageWrapper";
import { ShiftsView } from "@/components/shifts/ShiftsView";
import { ManageSharingModal } from "./ManageSharingModal";
import { SharingDropdown } from "./SharingDropdown";
import { useTranslations } from "@/lib/i18n/client";
import type { SharedUser, ShareRecipient } from "@/data-access/sharing";
import type { ShiftWithComputations, UserSettings, SupplementRule } from "@/lib/payroll";
import type { ShiftsAggregates } from "@/lib/services/shifts";

type SharingPageContentProps = {
  sharers: SharedUser[];
  recipients: ShareRecipient[];
  shareCapacity: { canAdd: boolean; currentCount: number; limit: number };
  selectedOwnerId: string | null;
  selectedSharer: SharedUser | null;
  sharedShifts: ShiftWithComputations[] | null;
  sharedSettings: UserSettings;
  sharedAggregates: ShiftsAggregates | null;
  presetRules: SupplementRule[];
};

export function SharingPageContent({
  sharers,
  recipients,
  shareCapacity,
  selectedOwnerId,
  selectedSharer,
  sharedShifts,
  sharedSettings,
  presetRules,
}: SharingPageContentProps) {
  const { t, locale } = useTranslations();
  const router = useRouter();
  const [manageSharingOpen, setManageSharingOpen] = useState(false);

  // Get translation strings with fallbacks
  const sharing = t.pages?.sharing ?? {
    title: "Deling",
    emptyTitle: "Ingen har delt med deg",
    emptyDescription: "Når noen deler vaktene sine med deg, vil de vises her.",
    viewShiftsFrom: "Vis vakter fra",
    manageSharing: "Administrer deling",
    shareYourShifts: "Del vaktene dine",
    selectSharer: "Velg en person",
    viewingShiftsFrom: "Viser vakter fra",
  };

  const handleSharerSelect = (sharerId: string | null) => {
    if (sharerId) {
      router.push(`/${locale}/sharing?view=${sharerId}`);
    } else {
      router.push(`/${locale}/sharing`);
    }
  };

  // If viewing a specific sharer's shifts
  if (selectedOwnerId && sharedShifts && selectedSharer) {
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
          headerSlot={
            <div className="flex items-center gap-2 w-full sm:justify-between sm:gap-3">
              <SharingDropdown
                sharers={sharers}
                selectedId={selectedOwnerId}
                onSelect={handleSharerSelect}
              />
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setManageSharingOpen(true)}
                className="gap-2 shrink-0"
              >
                <Settings className="h-4 w-4" />
                <span className="hidden sm:inline">{sharing.manageSharing}</span>
              </Button>
            </div>
          }
        />
        <ManageSharingModal
          isOpen={manageSharingOpen}
          onClose={() => setManageSharingOpen(false)}
          recipients={recipients}
          shareCapacity={shareCapacity}
        />
      </>
    );
  }

  // Default view: no sharer selected or no sharers at all
  return (
    <>
      <ScrollablePageWrapper>
        <div className="flex flex-col gap-6 px-4 pt-4">
          <div className="flex items-center justify-between gap-4">
            <h1 className="text-2xl font-semibold text-text-primary">{sharing.title}</h1>
            <Button
              variant="default"
              size="sm"
              onClick={() => setManageSharingOpen(true)}
              className="gap-2"
            >
              <Settings className="h-4 w-4" />
              {sharing.manageSharing}
            </Button>
          </div>

          {sharers.length > 0 ? (
            <div className="flex flex-col gap-4">
              <SharingDropdown
                sharers={sharers}
                selectedId={null}
                onSelect={handleSharerSelect}
                placeholder={sharing.selectSharer}
              />
            </div>
          ) : (
            <Card className="text-center py-12">
              <CardHeader>
                <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-surface-secondary">
                  <Users className="h-6 w-6 text-text-muted" />
                </div>
                <CardTitle>{sharing.emptyTitle}</CardTitle>
                <CardDescription>{sharing.emptyDescription}</CardDescription>
              </CardHeader>
            </Card>
          )}
        </div>
      </ScrollablePageWrapper>
      <ManageSharingModal
        isOpen={manageSharingOpen}
        onClose={() => setManageSharingOpen(false)}
        recipients={recipients}
        shareCapacity={shareCapacity}
      />
    </>
  );
}
