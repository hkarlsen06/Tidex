"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Bell, BellOff } from "lucide-react";
import { toggleSharerMuted } from "@/app/[locale]/(app)/sharing/_actions/sharing";

type MuteSharerToggleProps = {
  sharerId: string;
  isMuted: boolean;
  disabled?: boolean;
  translations: {
    mute: string;
    unmute: string;
  };
  onError?: (error: string) => void;
};

/**
 * Simple bell toggle button for muting/unmuting notifications from a sharer.
 * - Bell icon = notifications enabled
 * - BellOff icon = notifications muted
 */
export function MuteSharerToggle({
  sharerId,
  isMuted,
  disabled = false,
  translations,
  onError,
}: MuteSharerToggleProps) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [optimisticMuted, setOptimisticMuted] = useState(isMuted);

  const handleToggle = () => {
    if (disabled || isPending) return;

    const newMuted = !optimisticMuted;
    setOptimisticMuted(newMuted);

    startTransition(async () => {
      const result = await toggleSharerMuted(sharerId, newMuted);
      if (!result.success) {
        // Revert optimistic update
        setOptimisticMuted(isMuted);
        onError?.(result.error);
        router.refresh();
      }
    });
  };

  return (
    <button
      type="button"
      onClick={handleToggle}
      disabled={disabled || isPending}
      className={`
        p-1.5 rounded-md transition-colors
        ${optimisticMuted
          ? "text-text-muted hover:text-text-secondary"
          : "text-brand-gradient-start hover:text-brand-gradient-end"
        }
        ${disabled || isPending ? "opacity-50 cursor-not-allowed" : "hover:bg-surface-secondary"}
      `}
      title={optimisticMuted ? translations.unmute : translations.mute}
      aria-label={optimisticMuted ? translations.unmute : translations.mute}
    >
      {optimisticMuted ? (
        <BellOff className="h-4 w-4" />
      ) : (
        <Bell className="h-4 w-4" />
      )}
    </button>
  );
}
