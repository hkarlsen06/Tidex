"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { MouseEvent as ReactMouseEvent } from "react";
import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Settings, LogOut, Loader2, Globe } from "lucide-react";
import { ThemeToggle } from "./ThemeToggle";
import { LocaleToggle } from "./LocaleToggle";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "./AlertDialog";
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
  const [isLoggingOut, setIsLoggingOut] = useState(false);
  const [isLoggingOutGlobal, setIsLoggingOutGlobal] = useState(false);
  const [showLogoutEverywhereDialog, setShowLogoutEverywhereDialog] = useState(false);

  // Logout via route handler that clears cookies and returns HTML with client-side redirect
  // Can't use router.push() for route handlers - causes RSC payload errors
  const handleLogout = useCallback((event: ReactMouseEvent<HTMLAnchorElement>) => {
    event.preventDefault();
    if (isLoggingOut || isLoggingOutGlobal) return;

    setIsLoggingOut(true);
    window.location.href = "/logout";
  }, [isLoggingOut, isLoggingOutGlobal]);

  // Open confirmation dialog for global logout
  const handleLogoutEverywhereClick = useCallback((event: ReactMouseEvent<HTMLButtonElement>) => {
    event.preventDefault();
    if (isLoggingOut || isLoggingOutGlobal) return;
    setShowLogoutEverywhereDialog(true);
  }, [isLoggingOut, isLoggingOutGlobal]);

  // Execute global logout after confirmation
  const handleLogoutEverywhereConfirm = useCallback(() => {
    setIsLoggingOutGlobal(true);
    setShowLogoutEverywhereDialog(false);
    window.location.href = "/logout-global";
  }, []);

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
    // Treat "/" as "/dashboard" for consistent comparison
    if (path === "/") {
      return "/dashboard";
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

  const isSettingsDisabled = isOnboardingPath(pathname);

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
        className="flex items-center gap-3 rounded-2xl bg-background/80 pl-4 pr-2 py-2 border border-border/40 focus:outline-none focus:ring-2 focus:ring-border"
      >
        <span className="text-sm font-medium text-text-primary max-w-32 truncate">{displayName}</span>
        <span className="relative inline-flex h-8 w-8 items-center justify-center overflow-hidden rounded-xl bg-background text-xs font-semibold uppercase text-text-primary">
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
          className="absolute right-0 mt-2 w-56 overflow-hidden rounded-xl border border-border/40 bg-background shadow-app-lg"
        >
          <Link
            href="/settings"
            onClick={(event) => {
              if (isSettingsDisabled) {
                event.preventDefault();
                event.stopPropagation();
                return;
              }
              handleNavigationClick("/settings")(event);
            }}
            prefetch={true}
            role="menuitem"
            aria-disabled={isSettingsDisabled}
            tabIndex={isSettingsDisabled ? -1 : undefined}
            className={cn(
              "flex items-center gap-3 px-4 py-3.5 text-base text-text-primary hover:bg-accent",
              isSettingsDisabled && "cursor-not-allowed opacity-50 hover:bg-background"
            )}
          >
            <Settings strokeWidth={2} className="h-5 w-5" />
            {t.userMenu.settings}
          </Link>
          <ThemeToggle />
          <LocaleToggle />
          <Link
            href="/logout"
            onClick={handleLogout}
            prefetch={false}
            role="menuitem"
            aria-disabled={isLoggingOut || isLoggingOutGlobal}
            tabIndex={isLoggingOut || isLoggingOutGlobal ? -1 : undefined}
            className={cn(
              "flex items-center gap-3 px-4 py-3.5 text-base text-error hover:bg-error-subtle",
              (isLoggingOut || isLoggingOutGlobal) && "cursor-not-allowed opacity-70 hover:bg-transparent"
            )}
          >
            {isLoggingOut ? (
              <Loader2 strokeWidth={2} className="h-5 w-5 animate-spin" />
            ) : (
              <LogOut strokeWidth={2} className="h-5 w-5" />
            )}
            {t.userMenu.logout}
          </Link>
          <button
            type="button"
            onClick={handleLogoutEverywhereClick}
            role="menuitem"
            aria-disabled={isLoggingOut || isLoggingOutGlobal}
            tabIndex={isLoggingOut || isLoggingOutGlobal ? -1 : undefined}
            className={cn(
              "flex w-full items-center gap-3 px-4 py-3.5 text-base text-text-secondary hover:bg-accent text-left",
              (isLoggingOut || isLoggingOutGlobal) && "cursor-not-allowed opacity-70 hover:bg-transparent"
            )}
            disabled={isLoggingOut || isLoggingOutGlobal}
          >
            {isLoggingOutGlobal ? (
              <Loader2 strokeWidth={2} className="h-5 w-5 animate-spin" />
            ) : (
              <Globe strokeWidth={2} className="h-5 w-5" />
            )}
            {isLoggingOutGlobal ? t.userMenu.logoutEverywhereLoading : t.userMenu.logoutEverywhere}
          </button>
        </div>
      )}

      {/* Confirmation dialog for "Log out everywhere" */}
      <AlertDialog open={showLogoutEverywhereDialog} onOpenChange={setShowLogoutEverywhereDialog}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t.userMenu.logoutEverywhereConfirmTitle}</AlertDialogTitle>
            <AlertDialogDescription>
              {t.userMenu.logoutEverywhereConfirmDescription}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t.userMenu.logoutEverywhereConfirmCancel}</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleLogoutEverywhereConfirm}
              className="bg-error hover:bg-error/90"
            >
              {t.userMenu.logoutEverywhereConfirmAction}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
