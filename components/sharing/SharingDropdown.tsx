"use client";

import { useState, useRef, useEffect } from "react";
import Image from "next/image";
import { ChevronDown, User } from "lucide-react";
import { cn } from "@/lib/cn";
import type { SharedUser } from "@/data-access/sharing";

type SharingDropdownProps = {
  sharers: SharedUser[];
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
  selectedId,
  onSelect,
  placeholder = "Velg en person",
}: SharingDropdownProps) {
  const [open, setOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const selected = sharers.find((s) => s.id === selectedId);

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
    <div ref={dropdownRef} className="relative">
      <button
        type="button"
        onClick={() => setOpen(!open)}
        className={cn(
          "flex items-center gap-3 rounded-xl border border-border-subtle bg-surface-primary px-4 py-3 min-w-[200px]",
          "hover:bg-surface-secondary transition-colors",
          "focus:outline-none focus:ring-2 focus:ring-border"
        )}
      >
        {selected ? (
          <>
            <UserAvatar user={selected} />
            <span className="flex-1 text-left text-sm font-medium text-text-primary">
              {getDisplayName(selected)}
            </span>
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
          {sharers.map((sharer) => (
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
              <span className="text-sm font-medium text-text-primary">
                {getDisplayName(sharer)}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
