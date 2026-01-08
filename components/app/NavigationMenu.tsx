"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { useTranslations } from "@/lib/i18n/client";
import { clearSharingViewState } from "@/lib/hooks/useSharingViewState";
import {
  NavigationMenu as NavigationMenuPrimitive,
  NavigationMenuItem,
  NavigationMenuLink,
  NavigationMenuList,
  navigationMenuTriggerStyle,
} from "@ui/navigation-menu";

type NavItem = {
  href: string;
  labelKey: "home" | "shifts" | "stats" | "sharing";
};

const navItems: NavItem[] = [
  {
    href: "/dashboard",
    labelKey: "home",
  },
  {
    href: "/shifts",
    labelKey: "shifts",
  },
  {
    href: "/stats",
    labelKey: "stats",
  },
  {
    href: "/sharing",
    labelKey: "sharing",
  },
];

type NavigationMenuProps = {
  className?: string;
};

export function NavigationMenu({ className }: NavigationMenuProps) {
  const { t, locale } = useTranslations();
  const rawPathname = usePathname();

  // Strip locale prefix from pathname for consistent nav item matching
  // usePathname() returns paths like "/no/settings" or "/en/shifts"
  const pathname = rawPathname.replace(/^\/(no|en)(?=\/|$)/, "") || "/";

  // Check if currently on sharing path to determine sharing link behavior
  const isOnSharingPath = pathname.startsWith("/sharing");

  return (
    <NavigationMenuPrimitive className={className}>
      <NavigationMenuList>
        {navItems.map((item) => {
          // Dashboard is the home route - treat "/" as "/dashboard" for matching
          const normalizedPathname = pathname === "/" ? "/dashboard" : pathname;
          const isActive =
            item.href === "/dashboard"
              ? normalizedPathname === "/dashboard"
              : normalizedPathname.startsWith(item.href);

          // Always use base path without query params to avoid triggering parent loading states
          const href = `/${locale}${item.href}`;

          // Clear saved sharing state when clicking sharing link while on sharing path
          const handleClick =
            item.labelKey === "sharing" && isOnSharingPath
              ? () => clearSharingViewState()
              : undefined;

          return (
            <NavigationMenuItem key={item.href}>
              <NavigationMenuLink asChild>
                <Link
                  href={href}
                  onClick={handleClick}
                  className={cn(
                    navigationMenuTriggerStyle(),
                    isActive && "bg-accent/50 text-accent-foreground",
                  )}
                >
                  {t.navigation[item.labelKey]}
                </Link>
              </NavigationMenuLink>
            </NavigationMenuItem>
          );
        })}
      </NavigationMenuList>
    </NavigationMenuPrimitive>
  );
}
