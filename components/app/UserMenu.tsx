"use client";

import { useEffect, useRef, useState } from "react";
import type { MouseEvent as ReactMouseEvent } from "react";
import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { UserCircle, LogOut } from "lucide-react";
import { ThemeToggle } from "./ThemeToggle";
import { LocaleToggle } from "./LocaleToggle";
import { cn } from "@/lib/utils";
import { useNavigationFeedback } from "./navigation-feedback";
import { useTranslations } from "@/lib/i18n/client";

export function UserMenu({
  displayName,
  avatarUrl,
}: {
  displayName: string;
  avatarUrl: string | null;
}) {
  const { t } = useTranslations();
  const [open, setOpen] = useState(false);
  const btnRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const pathname = usePathname();
  const { navigate } = useNavigationFeedback();

  // Close menu on navigation
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => setOpen(false), [pathname]);

  const handleNavigationClick = (href: string) => (event: ReactMouseEvent<HTMLAnchorElement>) => {
    if (
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey ||
      event.button !== 0
    ) {
      return;
    }

    event.preventDefault();
    navigate(href);
  };

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

  const normalizePath = (path: string | null) => {
    if (!path) {
      return null;
    }
    if (path === "/") {
      return "/";
    }
    return path.replace(/\/+$/, "");
  };

  const isOnboardingPath = (path: string | null) => {
    const normalizedPath = normalizePath(path);
    if (!normalizedPath) {
      return false;
    }
    return (
      normalizedPath === "/onboarding" ||
      normalizedPath.startsWith("/onboarding/")
    );
  };

  const isProfileDisabled = isOnboardingPath(pathname);

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
        className="flex items-center gap-3 rounded-2xl bg-surface-secondary/80 pl-4 pr-2 py-2 shadow-app-sm dark:shadow-app-inner focus:outline-none focus:ring-2 focus:ring-border"
      >
        <span className="text-sm font-medium text-text-primary">{displayName}</span>
        <span className="relative inline-flex h-8 w-8 items-center justify-center overflow-hidden rounded-xl bg-surface-secondary text-xs font-semibold uppercase text-text-primary">
          {avatarUrl ? (
            <Image
              src={avatarUrl}
              alt={`${displayName} avatar`}
              fill
              sizes="32px"
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
            href="/settings/profile"
            onClick={(event) => {
              if (isProfileDisabled) {
                event.preventDefault();
                event.stopPropagation();
                return;
              }
              handleNavigationClick("/settings/profile")(event);
            }}
            prefetch={true}
            role="menuitem"
            aria-disabled={isProfileDisabled}
            tabIndex={isProfileDisabled ? -1 : undefined}
            className={cn(
              "flex items-center gap-2 px-4 py-2 text-sm text-text-primary hover:bg-surface-secondary/70",
              isProfileDisabled && "cursor-not-allowed opacity-50 hover:bg-surface-primary/95"
            )}
          >
            <UserCircle strokeWidth={2} className="h-4 w-4" />
            {t.userMenu.profile}
          </Link>
          <ThemeToggle />
          <LocaleToggle />
          <Link
            href="/logout"
            onClick={handleNavigationClick("/logout")}
            prefetch={false}
            role="menuitem"
            className="flex items-center gap-2 px-4 py-2 text-sm text-error hover:bg-error-subtle"
          >
            <LogOut strokeWidth={2} className="h-4 w-4" />
            {t.userMenu.logout}
          </Link>
        </div>
      )}
    </div>
  );
}
