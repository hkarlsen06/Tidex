"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, useEffect } from "react";
import type { MouseEvent } from "react";
import {
  Gauge,
  Calendar,
  Plus,
  ChartNoAxesCombined,
  Bolt,
  ArrowDown,
  ArrowLeft,
} from "lucide-react";
import { useNavigationFeedback } from "./navigation-feedback";
import { supabase } from "@/lib/supabase/browser";
import { useTranslations } from "@/lib/i18n/client";

type LucideIcon = typeof Gauge;
type NavItem = {
  href: string;
  label: string;
  icon: LucideIcon;
  isCenter?: boolean;
  matchPrefix?: boolean;
};

const navItems: NavItem[] = [
  {
    href: "/",
    label: "Home",
    icon: Gauge,
  },
  {
    href: "/shifts",
    label: "Shifts",
    icon: Calendar,
  },
  {
    href: "/shifts/add",
    label: "Add",
    icon: Plus,
    isCenter: true,
  },
  {
    href: "/stats",
    label: "Stats",
    icon: ChartNoAxesCombined,
  },
  {
    href: "/settings",
    label: "Settings",
    icon: Bolt,
    matchPrefix: true,
  },
];

export function NavBar() {
  const { t } = useTranslations();
  const rawPathname = usePathname();
  const { navigate, pendingPath } = useNavigationFeedback();
  const [showAddShiftHint, setShowAddShiftHint] = useState(false);

  // Strip locale prefix from pathname for consistent nav item matching
  // usePathname() returns paths like "/no/settings", "/en/shifts", or "/de/stats"
  const pathname = rawPathname.replace(/^\/(no|en|de)(?=\/|$)/, '') || '/';

  // Fetch shift count client-side to determine if hint should be shown
  // This is deferred to avoid blocking the initial render
  // Re-check when pathname changes so hint disappears after adding first shift
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

        // Update hint visibility based on current shift count
        setShowAddShiftHint((count ?? 0) === 0);
      } catch (err) {
        console.error("[NavBar] Unexpected error in shift count check:", err);
      }
    };

    checkShiftCount();
  }, [pathname]);

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

  const normalizedPath = normalizePath(pathname);
  const isOnSettingsSubPage = normalizedPath?.startsWith("/settings/") ?? false;

  return (
    <nav className="fixed left-0 right-0 z-40 bottom-0 md:bottom-4 md:bg-transparent">
      {/* Background that extends into safe area on mobile */}
      <div className="absolute inset-x-0 top-0 bottom-0 bg-surface-primary/95 backdrop-blur md:hidden" />

      <div className="relative mx-auto max-w-[520px] md:px-4 pb-[env(safe-area-inset-bottom)] md:pb-0">
        <div className="flex items-center justify-around pt-4 pb-4 border-t border-border-subtle md:bg-surface-primary/95 md:backdrop-blur md:border md:rounded-2xl md:shadow-app-lg">
          {navItems.map((item) => {
            const isActive = isPathActive(item);
            const Icon = item.icon;

            if (item.isCenter) {
              const isOnAddPage = pathname === "/shifts/add" || pendingPath === "/shifts/add";
              const targetHref = isOnAddPage ? "/shifts" : item.href;
              const shouldShowHint =
                showAddShiftHint &&
                !isOnAddPage &&
                (isEligibleForHint(pathname) || isEligibleForHint(pendingPath));

              return (
                <div
                  key={item.href}
                  className="relative flex items-center justify-center"
                >
                  {shouldShowHint ? (
                    <div className="pointer-events-none absolute bottom-[calc(100%+1.5rem)] left-1/2 flex -translate-x-1/2 flex-col items-center gap-3">
                      <span className="animate-gentle-pulse flex w-max flex-col items-center gap-0.5 rounded-lg border border-border-subtle bg-surface-primary px-3 py-1.5 text-center text-xs font-semibold text-text-primary shadow-app leading-tight">
                        <span>{t.navigation.addFirstShiftLine1}</span>
                        <span>{t.navigation.addFirstShiftLine2}</span>
                      </span>
                      <ArrowDown
                        className="h-10 w-10 text-brand-highlight animate-gentle-bob drop-shadow"
                        strokeWidth={2}
                      />
                    </div>
                  ) : null}
                  <Link
                    href={targetHref}
                    onClick={handleItemClick(targetHref)}
                    prefetch={true}
                    className="flex items-center justify-center p-2 -m-2"
                  >
                    <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand-gradientMid">
                      <Icon
                        className={`h-6 w-6 text-text-inverse transition-transform duration-200 ${
                          isOnAddPage ? "rotate-45" : ""
                        }`}
                        strokeWidth={2}
                      />
                    </div>
                  </Link>
                </div>
              );
            }

            // Show back arrow on settings icon when on sub-routes
            const isSettingsItem = item.href === "/settings";
            const showBackArrow = isSettingsItem && isOnSettingsSubPage;

            // Use ArrowLeft icon when on settings sub-page, otherwise use the item's icon
            const DisplayIcon = showBackArrow ? ArrowLeft : Icon;

            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={handleItemClick(item.href)}
                prefetch={true}
                className="flex items-center justify-center p-3 -m-3"
              >
                <DisplayIcon
                  className={`h-6 w-6 ${
                    isActive
                      ? "text-brand-highlight"
                      : "text-text-muted"
                  }`}
                  strokeWidth={isActive ? 2.5 : 2}
                />
              </Link>
            );
          })}
        </div>
      </div>
    </nav>
  );
}
