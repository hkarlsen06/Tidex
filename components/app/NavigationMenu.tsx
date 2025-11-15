"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { defaultLocale } from "@/lib/i18n/config";
import {
  NavigationMenu as NavigationMenuPrimitive,
  NavigationMenuItem,
  NavigationMenuLink,
  NavigationMenuList,
  navigationMenuTriggerStyle,
} from "@ui/navigation-menu";

type NavItem = {
  href: string;
  label: string;
};

const navItems: NavItem[] = [
  {
    href: "/",
    label: "Home",
  },
  {
    href: "/shifts",
    label: "Shifts",
  },
  {
    href: "/stats",
    label: "Stats",
  },
  {
    href: "/settings",
    label: "Settings",
  },
];

type NavigationMenuProps = {
  className?: string;
};

export function NavigationMenu({ className }: NavigationMenuProps) {
  const rawPathname = usePathname();

  // Strip locale prefix from pathname for consistent nav item matching
  // usePathname() returns paths like "/no/settings", "/en/shifts", or "/de/stats"
  const pathname = rawPathname.replace(/^\/(no|en|de)(?=\/|$)/, '') || '/';

  // Extract locale from current pathname
  const localeMatch = rawPathname.match(/^\/(en|no|de)/);
  const locale = localeMatch ? localeMatch[1] : defaultLocale;

  return (
    <NavigationMenuPrimitive className={className}>
      <NavigationMenuList>
        {navItems.map((item) => {
          const isActive =
            item.href === "/"
              ? pathname === "/"
              : pathname.startsWith(item.href);

          return (
            <NavigationMenuItem key={item.href}>
              <NavigationMenuLink asChild>
                <Link
                  href={`/${locale}${item.href}`}
                  className={cn(
                    navigationMenuTriggerStyle(),
                    isActive && "bg-accent/50 text-accent-foreground"
                  )}
                >
                  {item.label}
                </Link>
              </NavigationMenuLink>
            </NavigationMenuItem>
          );
        })}
      </NavigationMenuList>
    </NavigationMenuPrimitive>
  );
}
