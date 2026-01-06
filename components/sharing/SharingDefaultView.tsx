"use client";

import { useState, useEffect, useTransition, type ReactNode } from "react";
import { useRouter, usePathname } from "next/navigation";
import { Settings, Users, RefreshCw } from "lucide-react";
import { Button } from "@/components/app/Button";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/app/Card";
import { ScrollablePageWrapper } from "@/components/app/ScrollablePageWrapper";
import { ManageSharingModal } from "./ManageSharingModal";
import { useTranslations } from "@/lib/i18n/client";
import { refreshSharingData } from "@/app/[locale]/(app)/sharing/_actions/sharing";
import type { Friend } from "@/data-access/sharing";

type SharingDefaultViewProps = {
  friends: Friend[];
  shareCapacity: { canAdd: boolean; currentCount: number; limit: number };
  hasSharers: boolean;
  /** Slot for the sharers list - allows streaming via Suspense */
  children: ReactNode;
  /** Deep link: auto-open manage sharing modal (from share_started notification) */
  openManageModal?: boolean;
  /** Deep link: highlight this user ID in manage modal to prompt share back */
  highlightUserId?: string | null;
};

/**
 * Default view for the sharing page (no sharer selected)
 * Accepts children as a slot to enable Suspense streaming for the sharers list
 */
export function SharingDefaultView({
  friends,
  shareCapacity,
  hasSharers,
  children,
  openManageModal = false,
  highlightUserId = null,
}: SharingDefaultViewProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const pathname = usePathname();
  const [isRefreshing, startTransition] = useTransition();
  // Key to force remount of children after refresh (fixes Framer Motion animation issues)
  const [refreshKey, setRefreshKey] = useState(0);
  // Initialize modal state from prop - if openManageModal is true, start with modal open
  const [manageSharingOpen, setManageSharingOpen] = useState(openManageModal);

  const handleRefresh = () => {
    startTransition(async () => {
      await refreshSharingData();
      router.refresh();
      // Increment key to force remount of children, ensuring animations replay
      setRefreshKey((k) => k + 1);
    });
  };

  // Callback for modal when visibility changes (block/unblock)
  // The server action already invalidates cache and modal calls router.refresh(),
  // so this callback is intentionally empty. We keep it to allow future use
  // if needed, without having to change the ManageSharingModal interface.
  const handleVisibilityChange = () => {
    // No-op: server action + modal's router.refresh() handle data refresh
    // AnimatePresence with initial={false} handles new item animations
  };

  // Clean up URL params after modal opens from deep link
  useEffect(() => {
    if (openManageModal && manageSharingOpen) {
      // Remove manage and highlight params from URL to prevent re-opening on refresh
      router.replace(pathname, { scroll: false });
    }
  }, [openManageModal, manageSharingOpen, router, pathname]);

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

  return (
    <>
      <ScrollablePageWrapper pullToRefresh>
        <div className="flex flex-col gap-6 pt-4">
          <div className="flex items-center justify-between gap-4">
            <div className="flex items-center gap-2">
              <h1 className="text-2xl font-semibold text-text-primary">
                {sharing.title}
              </h1>
              <Button
                variant="ghost"
                size="icon"
                onClick={handleRefresh}
                disabled={isRefreshing}
              >
                <RefreshCw className={`h-4 w-4 ${isRefreshing ? "animate-spin" : ""}`} />
              </Button>
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={() => setManageSharingOpen(true)}
              className="gap-2"
            >
              <Settings className="h-4 w-4" />
              {sharing.manageSharing}
            </Button>
          </div>

          <div key={refreshKey}>
            {hasSharers ? (
              children
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
        </div>
      </ScrollablePageWrapper>
      <ManageSharingModal
        isOpen={manageSharingOpen}
        onCloseAction={() => setManageSharingOpen(false)}
        friends={friends}
        shareCapacity={shareCapacity}
        highlightUserId={highlightUserId}
        onVisibilityChange={handleVisibilityChange}
      />
    </>
  );
}
