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
} from "@tabler/icons-react";
import { useNavigationFeedback } from "./navigation-feedback";

type TablerIcon = typeof IconHome;
type NavItem = { 
  href: string; 
  label: string; 
  icon: TablerIcon; 
  iconFilled: TablerIcon;
  isCenter?: boolean;
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
  },
];

export function NavBar() {
  const pathname = usePathname();
  const { navigate, pendingPath } = useNavigationFeedback();

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

  const isPathActive = (href: string) => pathname === href || pendingPath === href;

  return (
    <nav className="fixed bottom-4 left-0 right-0 z-40" style={{ paddingBottom: 'env(safe-area-inset-bottom)' }}>
      <div className="mx-auto max-w-[480px] px-4">
        <div className="flex items-center justify-around rounded-full border border-border-subtle bg-surface-primary/80 px-6 py-3 shadow-app-lg backdrop-blur">
          {navItems.map((item) => {
            const isActive = isPathActive(item.href);
            const Icon = isActive && !item.isCenter ? item.iconFilled : item.icon;

            if (item.isCenter) {
              const isOnAddPage = pathname === "/shifts/add";
              const targetHref = isOnAddPage ? "/shifts" : item.href;

              return (
                <Link
                  key={item.href}
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
