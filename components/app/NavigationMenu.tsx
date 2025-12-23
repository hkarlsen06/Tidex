"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { useTranslations } from "@/lib/i18n/client";
import {
  NavigationMenu as NavigationMenuPrimitive,
  NavigationMenuItem,
  NavigationMenuLink,
  NavigationMenuList,
  navigationMenuTriggerStyle,
} from "@ui/navigation-menu";

type NavItem = {
  href: string;
  labelKey: 'home' | 'shifts' | 'stats' | 'sharing';
};

const navItems: NavItem[] = [
  {
    href: "/",
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
  const pathname = rawPathname.replace(/^\/(no|en)(?=\/|$)/, '') || '/';

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
