"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
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
} from "@tabler/icons-react";
import { useNavigationFeedback } from "./navigation-feedback";

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

type NavBarProps = {
  showAddShiftHint?: boolean;
};

export function NavBar({ showAddShiftHint = false }: NavBarProps) {
  const pathname = usePathname();
  const { navigate, pendingPath } = useNavigationFeedback();

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

  return (
    <nav className="fixed bottom-4 left-0 right-0 z-40" style={{ paddingBottom: 'env(safe-area-inset-bottom)' }}>
      <div className="mx-auto max-w-[480px] px-4">
        <div className="flex items-center justify-around rounded-full border border-border-subtle bg-surface-primary/80 px-6 py-3 shadow-app-lg backdrop-blur">
          {navItems.map((item) => {
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
                    className="flex items-center justify-center"
                  >
                    <div className="flex h-10 w-10 items-center justify-center rounded-full bg-brand-gradientMid">
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

            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={handleItemClick(item.href)}
                className="flex items-center justify-center"
              >
                <Icon
                  className={
                    isActive
                      ? "h-6 w-6 text-text-primary"
                      : "h-6 w-6 text-text-muted"
                  }
                  stroke={2}
                />
              </Link>
            );
          })}
        </div>
      </div>
    </nav>
  );
}
