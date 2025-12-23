"use client";

import { useState, useRef, useEffect } from "react";
import Image from "next/image";
import { ChevronDown, User } from "lucide-react";
import { cn } from "@/lib/cn";
import type { SharedUser, SharerShiftPreview } from "@/data-access/sharing";

type SharingDropdownProps = {
  sharers: SharedUser[];
  shiftPreviews?: SharerShiftPreview[];
  selectedId: string | null;
  onSelect: (id: string | null) => void;
  placeholder?: string;
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

function UserAvatar({ user, size = "sm" }: { user: SharedUser; size?: "sm" | "md" }) {
  // Resolve avatar URL with fallback chain: custom profile pic > OAuth avatar > initials
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

export function SharingDropdown({
  sharers,
  shiftPreviews = [],
  selectedId,
  onSelect,
  placeholder = "Velg en person",
}: SharingDropdownProps) {
  const [open, setOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const selected = sharers.find((s) => s.id === selectedId);

  // Sort sharers by shift preview order (which is pre-sorted by the server)
  // Sharers with previews come first (in preview order), then sharers without
  const sharerMap = new Map(sharers.map(s => [s.id, s]));
  const previewMap = new Map(shiftPreviews.map(p => [p.sharerId, p]));
  const sortedSharers = shiftPreviews.length > 0
    ? [
        ...shiftPreviews.map(p => sharerMap.get(p.sharerId)).filter(Boolean) as SharedUser[],
        ...sharers.filter(s => !previewMap.has(s.id)),
      ]
    : sharers;

  // Close on click outside
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  return (
    <div ref={dropdownRef} className="relative w-full">
      <button
        type="button"
        onClick={() => setOpen(!open)}
        className={cn(
          "flex w-full items-center gap-3 rounded-xl border border-border-subtle bg-surface-primary px-4 py-3",
          "hover:bg-surface-secondary transition-colors",
          "focus:outline-none focus:ring-2 focus:ring-border"
        )}
      >
        {selected ? (
          <>
            <UserAvatar user={selected} />
            <div className="flex flex-1 flex-col text-left min-w-0">
              <span className="text-sm font-medium text-text-primary truncate-fade">
                {getDisplayName(selected)}
              </span>
              {getSecondaryInfo(selected) && (
                <span className="text-xs text-text-muted truncate-fade">
                  {getSecondaryInfo(selected)}
                </span>
              )}
            </div>
          </>
        ) : (
          <>
            <span className="inline-flex h-8 w-8 items-center justify-center rounded-full bg-surface-secondary">
              <User className="h-4 w-4 text-text-muted" />
            </span>
            <span className="flex-1 text-left text-sm text-text-secondary">{placeholder}</span>
          </>
        )}
        <ChevronDown
          className={cn(
            "h-4 w-4 text-text-muted transition-transform",
            open && "rotate-180"
          )}
        />
      </button>

      {open && (
        <div className="absolute left-0 top-full z-50 mt-2 w-full min-w-[200px] overflow-hidden rounded-xl border border-border-subtle bg-surface-primary shadow-lg">
          {sortedSharers.map((sharer) => (
            <button
              key={sharer.id}
              type="button"
              onClick={() => {
                onSelect(sharer.id);
                setOpen(false);
              }}
              className={cn(
                "flex w-full items-center gap-3 px-4 py-3 text-left",
                "hover:bg-surface-secondary transition-colors",
                selectedId === sharer.id && "bg-surface-secondary"
              )}
            >
              <UserAvatar user={sharer} />
              <div className="flex flex-col min-w-0 flex-1">
                <span className="text-sm font-medium text-text-primary truncate-fade">
                  {getDisplayName(sharer)}
                </span>
                {getSecondaryInfo(sharer) && (
                  <span className="text-xs text-text-muted truncate-fade">
                    {getSecondaryInfo(sharer)}
                  </span>
                )}
              </div>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
