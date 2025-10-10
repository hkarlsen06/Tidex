"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { ThemeToggle } from "./ThemeToggle";

export function UserMenu({
  displayName,
  avatarUrl,
}: {
  displayName: string;
  avatarUrl: string | null;
}) {
  const [open, setOpen] = useState(false);
  const btnRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const pathname = usePathname();

  useEffect(() => setOpen(false), [pathname]);

  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      if (!open) return;
      const t = e.target as Node;
      if (menuRef.current?.contains(t) || btnRef.current?.contains(t)) return;
      setOpen(false);
    }
    document.addEventListener("mousedown", onDocClick);
    return () => document.removeEventListener("mousedown", onDocClick);
  }, [open]);

  return (
    <div className="relative">
      <button
        ref={btnRef}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls="user-menu"
        onClick={() => setOpen((v) => !v)}
        onKeyDown={(e) => {
          if (e.key === "Escape") setOpen(false);
          if (e.key === "ArrowDown") setOpen(true);
        }}
        className="flex items-center gap-3 rounded-full bg-surface-secondary/80 px-3 py-1 shadow-app-sm dark:shadow-app-inner focus:outline-none focus:ring-2 focus:ring-border"
      >
        <span className="text-sm font-medium text-text-primary">{displayName}</span>
        <span className="relative inline-flex h-10 w-10 items-center justify-center overflow-hidden rounded-full bg-surface-secondary text-sm font-semibold uppercase text-text-primary">
          {avatarUrl ? (
            <Image
              src={avatarUrl}
              alt={`${displayName} avatar`}
              fill
              sizes="40px"
              className="object-cover"
              unoptimized
            />
          ) : (
            displayName.charAt(0).toUpperCase() || "?"
          )}
        </span>
      </button>

      {open && (
        <div
          id="user-menu"
          ref={menuRef}
          role="menu"
          aria-label="User menu"
          className="absolute right-0 mt-2 w-48 overflow-hidden rounded-xl border border-border-subtle bg-surface-primary/95 shadow-app-lg backdrop-blur"
        >
          <Link
            href="/settings"
            role="menuitem"
            className="block px-4 py-2 text-sm text-text-primary hover:bg-surface-secondary/70"
          >
            Profil
          </Link>
          <ThemeToggle />
          <Link
            href="/logout"
            prefetch={false}
            role="menuitem"
            className="block px-4 py-2 text-sm text-error hover:bg-error-subtle"
          >
            Logg ut
          </Link>
        </div>
      )}
    </div>
  );
}
