"use client";

import { useState } from "react";
import Image from "next/image";
import { ChevronRight, Loader2 } from "lucide-react";
import { cn } from "@/lib/cn";
import type { SharedUser } from "@/data-access/sharing";

type SharersListProps = {
  sharers: SharedUser[];
  onSelect: (id: string) => void;
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
  // Strip country code and non-digits
  const digits = phone.replace(/\D/g, "");
  const localNumber = digits.startsWith("47") && digits.length === 10
    ? digits.slice(2)
    : digits;

  // Format as NNN NN NNN if 8 digits
  if (localNumber.length === 8) {
    return `${localNumber.slice(0, 3)} ${localNumber.slice(3, 5)} ${localNumber.slice(5)}`;
  }
  return localNumber;
}

function getSecondaryInfo(sharer: SharedUser): string | null {
  // Priority: phone first, then email, then nothing
  if (sharer.phone) return formatPhoneNumber(sharer.phone);
  if (sharer.email) return sharer.email;
  return null;
}

function UserAvatar({ user, size = "md" }: { user: SharedUser; size?: "sm" | "md" }) {
  const avatarUrl = user.profilePictureUrl || user.oauthAvatarUrl || null;
  const sizeClasses = size === "sm" ? "h-8 w-8 text-xs" : "h-10 w-10 text-sm";
  const imageSizes = size === "sm" ? "32px" : "40px";

  if (avatarUrl) {
    return (
      <span className={cn("relative inline-flex items-center justify-center overflow-hidden rounded-full bg-surface-secondary font-semibold text-text-primary", sizeClasses)}>
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
    <span className={cn("inline-flex items-center justify-center rounded-full bg-surface-secondary font-semibold text-text-primary", sizeClasses)}>
      {getInitials(user.firstName ?? user.email)}
    </span>
  );
}

export function SharersList({ sharers, onSelect }: SharersListProps) {
  const [loadingId, setLoadingId] = useState<string | null>(null);

  const handleClick = (id: string) => {
    setLoadingId(id);
    onSelect(id);
  };

  return (
    <div className="flex flex-col gap-2">
      {sharers.map((sharer) => {
        const isLoading = loadingId === sharer.id;
        return (
          <button
            key={sharer.id}
            type="button"
            onClick={() => handleClick(sharer.id)}
            disabled={loadingId !== null}
            className={cn(
              "flex w-full items-center gap-3 rounded-xl border border-border-subtle bg-surface-primary px-4 py-3 text-left",
              "hover:bg-surface-secondary transition-colors",
              "focus:outline-none focus:ring-2 focus:ring-border",
              loadingId !== null && !isLoading && "opacity-50"
            )}
          >
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
          </button>
        );
      })}
    </div>
  );
}
