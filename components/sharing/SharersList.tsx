"use client";

import { useEffect, useMemo, useState } from "react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "motion/react";
import { ChevronRight, Loader2 } from "lucide-react";
import { cn } from "@/lib/cn";
import { SharedUserShiftPreview } from "./SharedUserShiftPreview";
import type { SharedUser, SharerShiftPreview } from "@/data-access/sharing";

type SharersListProps = {
  sharers: SharedUser[];
  shiftPreviews?: SharerShiftPreview[];
  onSelectAction?: (id: string) => void;
  /** Base path for navigation when onSelectAction is not provided */
  basePath?: string;
};

function getInitials(name: string | null | undefined): string {
  if (!name) return "?";
  return name
    .split(" ")
    .map((n) => n[0])
    .join("")
    .toUpperCase()
    .slice(0, 2);
}

function getDisplayName(sharer: SharedUser): string {
  if (sharer.firstName) return sharer.firstName;
  if (sharer.email) return sharer.email.split("@")[0];
  return "Bruker";
}

function formatPhoneNumber(phone: string): string {
  const digits = phone.replace(/\D/g, "");
  const localNumber =
    digits.startsWith("47") && digits.length === 10 ? digits.slice(2) : digits;

  if (localNumber.length === 8) {
    return `${localNumber.slice(0, 3)} ${localNumber.slice(3, 5)} ${localNumber.slice(5)}`;
  }
  return localNumber;
}

function getSecondaryInfo(sharer: SharedUser): string | null {
  if (sharer.phone) return formatPhoneNumber(sharer.phone);
  if (sharer.email) return sharer.email;
  return null;
}

function UserAvatar({
  user,
  size = "md",
}: {
  user: SharedUser;
  size?: "sm" | "md";
}) {
  const avatarUrl = user.profilePictureUrl || user.oauthAvatarUrl || null;
  const sizeClasses = size === "sm" ? "h-8 w-8 text-xs" : "h-10 w-10 text-sm";
  const imageSizes = size === "sm" ? "32px" : "40px";

  if (avatarUrl) {
    return (
      <span
        className={cn(
          "relative inline-flex items-center justify-center overflow-hidden rounded-full bg-surface-secondary font-semibold text-text-primary",
          sizeClasses,
        )}
      >
        <Image
          src={avatarUrl}
          alt={getDisplayName(user)}
          fill
          sizes={imageSizes}
          className="object-cover"
          unoptimized
        />
      </span>
    );
  }

  return (
    <span
      className={cn(
        "inline-flex items-center justify-center rounded-full bg-surface-secondary font-semibold text-text-primary",
        sizeClasses,
      )}
    >
      {getInitials(user.firstName ?? user.email)}
    </span>
  );
}

export function SharersList({
  sharers,
  shiftPreviews = [],
  onSelectAction,
  basePath,
}: SharersListProps) {
  const router = useRouter();
  const [loadingId, setLoadingId] = useState<string | null>(null);
  const prefetchIds = useMemo(
    () => sharers.map((sharer) => sharer.id),
    [sharers],
  );

  useEffect(() => {
    if (!basePath || prefetchIds.length === 0) return;
    const connection =
      typeof navigator !== "undefined"
        ? (navigator as Navigator & { connection?: { saveData?: boolean } })
            .connection
        : undefined;

    if (connection?.saveData) return;

    let cancelled = false;
    let index = 0;
    const schedule = (cb: () => void) => {
      const idleCallback =
        typeof window !== "undefined"
          ? (
              window as Window & {
                requestIdleCallback?: (
                  callback: () => void,
                  options?: { timeout: number },
                ) => number;
              }
            ).requestIdleCallback
          : undefined;

      if (idleCallback) {
        idleCallback(cb, { timeout: 1000 });
      } else {
        setTimeout(cb, 200);
      }
    };

    const run = () => {
      if (cancelled || index >= prefetchIds.length) return;
      const sharerId = prefetchIds[index];
      index += 1;
      router.prefetch(`${basePath}?view=${sharerId}`);
      schedule(run);
    };

    schedule(run);
    return () => {
      cancelled = true;
    };
  }, [basePath, prefetchIds, router]);

  const handleClick = (id: string) => {
    setLoadingId(id);
    if (onSelectAction) {
      onSelectAction(id);
    } else if (basePath) {
      router.push(`${basePath}?view=${id}`);
    }
  };

  // Create a lookup map for sharers and previews
  const sharerMap = new Map(sharers.map((s) => [s.id, s]));
  const previewMap = new Map(shiftPreviews.map((p) => [p.sharerId, p]));

  // Sort sharers by shift preview order (which is pre-sorted by the server)
  // Sharers with previews come first (in preview order), then sharers without
  const sortedSharers =
    shiftPreviews.length > 0
      ? [
          ...(shiftPreviews
            .map((p) => sharerMap.get(p.sharerId))
            .filter(Boolean) as SharedUser[]),
          ...sharers.filter((s) => !previewMap.has(s.id)),
        ]
      : sharers;

  return (
    <div className="flex flex-col gap-3">
      <AnimatePresence mode="popLayout" initial={false}>
        {sortedSharers.map((sharer) => {
          const isLoading = loadingId === sharer.id;
          const preview = previewMap.get(sharer.id);
          const hasShiftPreview = preview?.shift && preview?.status;

          return (
            <motion.button
              key={sharer.id}
              layout
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10, transition: { duration: 0.15 } }}
              transition={{
                type: "spring",
                stiffness: 300,
                damping: 30,
              }}
              type="button"
              onClick={() => handleClick(sharer.id)}
              disabled={loadingId !== null}
              className={cn(
                "w-full text-left rounded-xl border border-border-subtle bg-surface-primary overflow-hidden",
                "hover:bg-surface-secondary transition-colors",
                "focus:outline-none focus:ring-2 focus:ring-border",
                loadingId !== null && !isLoading && "opacity-50",
              )}
            >
              {/* User card header */}
              <div className="flex w-full items-center gap-3 px-4 py-3">
                <UserAvatar user={sharer} size="md" />
                <div className="flex flex-1 flex-col min-w-0">
                  <span className="text-sm font-medium text-text-primary truncate-fade">
                    {getDisplayName(sharer)}
                  </span>
                  {getSecondaryInfo(sharer) && (
                    <span className="text-xs text-text-muted truncate-fade">
                      {getSecondaryInfo(sharer)}
                    </span>
                  )}
                </div>
                {isLoading ? (
                  <Loader2 className="h-4 w-4 text-text-muted animate-spin" />
                ) : (
                  <ChevronRight className="h-4 w-4 text-text-muted" />
                )}
              </div>

              {/* Shift preview - shown under the user card */}
              {hasShiftPreview && (
                <div className="px-3 pb-3">
                  <SharedUserShiftPreview
                    shift={preview.shift!}
                    status={preview.status!}
                  />
                </div>
              )}
            </motion.button>
          );
        })}
      </AnimatePresence>
    </div>
  );
}
