"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, useEffect } from "react";
import type { MouseEvent } from "react";
import {
  IconHome,
  IconHomeFilled,
  IconCalendarWeek,
  IconCalendarWeekFilled,
  IconPlus,
  IconStack,
  IconStackFilled,
  IconSettings,
  IconSettingsFilled,
  IconArrowDown,
  IconX,
  IconSettingsShare,
} from "@tabler/icons-react";
import { useNavigationFeedback } from "./navigation-feedback";
import { useScrollDirection } from "./use-scroll-direction";
import { supabase } from "@/lib/supabase/browser";

type TablerIcon = typeof IconHome;
type NavItem = {
  href: string;
  label: string;
  icon: TablerIcon;
  iconFilled: TablerIcon;
  isCenter?: boolean;
  matchPrefix?: boolean;
};

const navItems: NavItem[] = [
  {
    href: "/",
    label: "Home",
    icon: IconHome,
    iconFilled: IconHomeFilled,
  },
  {
    href: "/shifts",
    label: "Shifts",
    icon: IconCalendarWeek,
    iconFilled: IconCalendarWeekFilled,
  },
  {
    href: "/shifts/add",
    label: "Add",
    icon: IconPlus,
    iconFilled: IconPlus,
    isCenter: true,
  },
  {
    href: "/stats",
    label: "Stats",
    icon: IconStack,
    iconFilled: IconStackFilled,
  },
  {
    href: "/settings",
    label: "Settings",
    icon: IconSettings,
    iconFilled: IconSettingsFilled,
    matchPrefix: true,
  },
];

export function NavBar() {
  const pathname = usePathname();
  const { navigate, pendingPath } = useNavigationFeedback();
  const { scrollDirection, scrollY } = useScrollDirection(50);
  const [showAddShiftHint, setShowAddShiftHint] = useState(false);

  // Fetch shift count client-side to determine if hint should be shown
  // This is deferred to avoid blocking the initial render
  useEffect(() => {
    const checkShiftCount = async () => {
      try {
        const { data: { user }, error: userError } = await supabase.auth.getUser();
        if (userError || !user) {
          console.warn("[NavBar] Failed to get user for shift count check:", userError);
          return;
        }

        const { count, error } = await supabase
          .from("user_shifts")
          .select("id", { count: "exact", head: true })
          .eq("user_id", user.id);

        if (error) {
          console.warn("[NavBar] Failed to check shift count:", error);
          return;
        }

        if ((count ?? 0) === 0) {
          setShowAddShiftHint(true);
        }
      } catch (err) {
        console.error("[NavBar] Unexpected error in shift count check:", err);
      }
    };

    checkShiftCount();
  }, []);

  const isOnboardingPath = (path: string | null) => {
    if (typeof path !== "string") {
      return false;
    }

    const normalizedPath = normalizePath(path);
    return Boolean(
      normalizedPath &&
        (normalizedPath === "/onboarding" || normalizedPath.startsWith("/onboarding/"))
    );
  };

  if (isOnboardingPath(pathname) || isOnboardingPath(pendingPath)) {
    return null;
  }

  const handleItemClick = (href: string) => (event: MouseEvent<HTMLAnchorElement>) => {
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

  function normalizePath(path: string | null) {
    if (!path) {
      return null;
    }
    if (path === "/") {
      return "/";
    }
    return path.replace(/\/+$/, "");
  }

  const isEligibleForHint = (path: string | null) => {
    const normalizedPath = normalizePath(path);
    if (!normalizedPath) {
      return false;
    }
    return normalizedPath === "/" || normalizedPath === "/shifts";
  };

  const isPathActive = (item: NavItem) => {
    const normalizedHref = normalizePath(item.href);
    if (!normalizedHref) {
      return false;
    }

    const matches = (path: string | null) => {
      const normalizedPath = normalizePath(path);
      if (!normalizedPath || !normalizedHref) {
        return false;
      }

      if (normalizedHref === "/") {
        return normalizedPath === "/";
      }

      if (normalizedPath === normalizedHref) {
        return true;
      }

      if (!item.matchPrefix) {
        return false;
      }

      return normalizedPath.startsWith(`${normalizedHref}/`);
    };

    return matches(pathname) || matches(pendingPath);
  };

  // Determine if navbar should be minimized
  const shouldMinimize = () => {
    if (scrollDirection !== "down" || scrollY < 100) {
      return false;
    }

    const normalizedPath = normalizePath(pathname);
    if (!normalizedPath) {
      return false;
    }

    // Minimize on /stats route only (not /settings since it has little content)
    const shouldMinimizeToHome = normalizedPath === "/stats";

    // Minimize on /settings/* sub-routes (but not /settings itself)
    const shouldMinimizeToSettings =
      normalizedPath.startsWith("/settings/");

    // Minimize on /shifts and /shifts/add routes to close button
    const shouldMinimizeToClose =
      normalizedPath === "/shifts/add" || normalizedPath === "/shifts";

    return shouldMinimizeToHome || shouldMinimizeToSettings || shouldMinimizeToClose;
  };

  const isMinimized = shouldMinimize();
  const normalizedPath = normalizePath(pathname);
  const isOnAddPage = normalizedPath === "/shifts/add";
  const isOnShiftsPage = normalizedPath === "/shifts";
  const isOnSettingsSubPage = normalizedPath?.startsWith("/settings/") ?? false;
  const minimizeToClose = isMinimized && isOnAddPage;
  const minimizeToPlus = isMinimized && isOnShiftsPage;
  const minimizeToSettings = isMinimized && isOnSettingsSubPage;

  return (
    <nav className="fixed bottom-4 left-0 right-0 z-40" style={{ paddingBottom: 'env(safe-area-inset-bottom)' }}>
      <div className={`mx-auto max-w-[480px] px-4 transition-all duration-500 ease-in-out ${isMinimized ? (minimizeToClose || minimizeToPlus ? "" : minimizeToSettings ? "flex justify-end" : "!px-4") : ""}`}>
        <div className={`flex items-center rounded-3xl border border-border-subtle bg-surface-primary/80 shadow-app-lg backdrop-blur transition-all duration-500 ease-in-out ${
          isMinimized
            ? minimizeToClose || minimizeToPlus
              ? "w-16 mx-auto justify-center px-4 py-3"
              : minimizeToSettings
              ? "w-16 justify-center px-4 py-3"
              : "w-16 justify-center px-4 py-3"
            : "justify-around px-6 py-3"
        }`}>
          {isMinimized ? (
            minimizeToClose ? (
              // Minimized to close button in center for /shifts/add
              <Link
                href="/shifts"
                onClick={handleItemClick("/shifts")}
                className="flex items-center justify-center p-2 -m-2 navbar-icon-fade-in"
              >
                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-gradientMid navbar-scale-in">
                  <IconX className="h-6 w-6 text-text-inverse transition-transform duration-200" stroke={2} />
                </div>
              </Link>
            ) : minimizeToPlus ? (
              // Minimized to plus button in center for /shifts
              <Link
                href="/shifts/add"
                onClick={handleItemClick("/shifts/add")}
                className="flex items-center justify-center p-2 -m-2 navbar-icon-fade-in"
              >
                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-gradientMid navbar-scale-in">
                  <IconPlus className="h-6 w-6 text-text-inverse" stroke={2} />
                </div>
              </Link>
            ) : minimizeToSettings ? (
              // Minimized to settings share icon for sub-routes
              <Link
                href="/settings"
                onClick={handleItemClick("/settings")}
                className="flex items-center justify-center p-3 -m-3 navbar-icon-fade-in"
              >
                <IconSettingsShare className="h-6 w-6 text-text-primary navbar-scale-in" stroke={2} />
              </Link>
            ) : (
              // Minimized to home icon on left
              <Link
                href="/"
                onClick={handleItemClick("/")}
                className="flex items-center justify-center p-3 -m-3 navbar-icon-fade-in"
              >
                <IconHome className="h-6 w-6 text-text-primary navbar-scale-in" stroke={2} />
              </Link>
            )
          ) : (
            navItems.map((item) => {
            const isActive = isPathActive(item);
            const Icon = isActive && !item.isCenter ? item.iconFilled : item.icon;

            if (item.isCenter) {
              const isOnAddPage = pathname === "/shifts/add" || pendingPath === "/shifts/add";
              const targetHref = isOnAddPage ? "/shifts" : item.href;
              const shouldShowHint =
                showAddShiftHint &&
                !isOnAddPage &&
                (isEligibleForHint(pathname) || isEligibleForHint(pendingPath));

              return (
                <div key={item.href} className="relative flex items-center justify-center">
                  {shouldShowHint ? (
                    <div className="pointer-events-none absolute bottom-[calc(100%+1.5rem)] left-1/2 flex -translate-x-1/2 flex-col items-center gap-3">
                      <span className="animate-gentle-pulse flex w-max flex-col items-center gap-0.5 rounded-lg border border-border-subtle bg-surface-primary px-3 py-1.5 text-center text-xs font-semibold text-text-primary shadow-app leading-tight">
                        <span>Legg til din</span>
                        <span>første vakt!</span>
                      </span>
                      <IconArrowDown
                        className="h-10 w-10 text-brand-highlight animate-gentle-bob drop-shadow"
                        stroke={2}
                      />
                    </div>
                  ) : null}
                  <Link
                    href={targetHref}
                    onClick={handleItemClick(targetHref)}
                    className="flex items-center justify-center p-2 -m-2"
                  >
                    <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-gradientMid">
                      <Icon
                        className={`h-6 w-6 text-text-inverse transition-transform duration-200 ${
                          isOnAddPage ? "rotate-45" : ""
                        }`}
                        stroke={2}
                      />
                    </div>
                  </Link>
                </div>
              );
            }

            // Show back arrow badge on settings icon when on sub-routes
            const isSettingsItem = item.href === "/settings";
            const showSettingsBadge = isSettingsItem && isOnSettingsSubPage;

            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={handleItemClick(item.href)}
                className="flex items-center justify-center p-3 -m-3 navbar-icon-fade-in"
              >
                {showSettingsBadge ? (
                  <IconSettingsShare
                    className={`navbar-scale-in ${
                      isActive
                        ? "h-6 w-6 text-text-primary"
                        : "h-6 w-6 text-text-muted"
                    }`}
                    stroke={2}
                  />
                ) : (
                  <Icon
                    className={`navbar-scale-in ${
                      isActive
                        ? "h-6 w-6 text-text-primary"
                        : "h-6 w-6 text-text-muted"
                    }`}
                    stroke={2}
                  />
                )}
              </Link>
            );
          })
          )}
        </div>
      </div>
    </nav>
  );
}
