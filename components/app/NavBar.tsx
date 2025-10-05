"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
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

type NavItem = {
  href: string;
  label: string;
  icon: React.ComponentType<{ stroke?: number; className?: string }>;
  iconFilled: React.ComponentType<{ className?: string }>;
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

  return (
    <nav className="fixed bottom-4 left-0 right-0 z-40">
      <div className="mx-auto max-w-[480px] px-4">
        <div className="flex items-center justify-around rounded-full border border-border-subtle bg-surface-primary/80 px-6 py-3 shadow-lg backdrop-blur dark:shadow-slate-950/40">
          {navItems.map((item) => {
            const isActive = pathname === item.href;
            const Icon = isActive && !item.isCenter ? item.iconFilled : item.icon;

            if (item.isCenter) {
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className="flex items-center justify-center"
                >
                  <div className="flex h-10 w-10 items-center justify-center rounded-full bg-brand-gradientMid">
                    <Icon className="h-6 w-6 text-text-inverse" stroke={2} />
                  </div>
                </Link>
              );
            }

            return (
              <Link
                key={item.href}
                href={item.href}
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
