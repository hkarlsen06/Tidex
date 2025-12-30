"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useSyncExternalStore, useState, useEffect, type MouseEvent } from "react";
import { Card } from "@/components/app/Card";
import { Separator } from "@/components/app/Separator";
import {
  User,
  Banknote,
  Palette,
  Database,
  CreditCard,
  Shield,
  Bell,
  ChevronRight,
  Loader2,
  ShieldAlert,
} from "lucide-react";
import { useNavigationFeedback } from "@/components/app/navigation-feedback";
import { useTranslations } from "@/lib/i18n/client";
import type { Dictionary } from "@/lib/i18n/dictionaries/no";
import { cn } from "@/lib/cn";
import { defaultLocale } from "@/lib/i18n/config";
import { isNativePlatform } from "@/lib/capacitor/platform";
import { supabase } from "@/lib/supabase/browser";

interface SettingsItem {
  href: string;
  label: string;
  description: string;
  icon: typeof User;
  adminOnly?: boolean;
}

const getSettingsItems = (t: Dictionary, showNotifications: boolean, showAdmin: boolean): SettingsItem[] => {
  const items: SettingsItem[] = [
    {
      href: "/settings/profile",
      label: t.pages.settings.menu.profile.label,
      description: t.pages.settings.menu.profile.description,
      icon: User,
    },
    {
      href: "/settings/pay",
      label: t.pages.settings.menu.pay.label,
      description: t.pages.settings.menu.pay.description,
      icon: Banknote,
    },
    {
      href: "/settings/security",
      label: t.pages.settings.menu.security.label,
      description: t.pages.settings.menu.security.description,
      icon: Shield,
    },
    {
      href: "/settings/subscription",
      label: t.pages.settings.menu.subscription.label,
      description: t.pages.settings.menu.subscription.description,
      icon: CreditCard,
    },
    {
      href: "/settings/display",
      label: t.pages.settings.menu.display.label,
      description: t.pages.settings.menu.display.description,
      icon: Palette,
    },
    {
      href: "/settings/data",
      label: t.pages.settings.menu.data.label,
      description: t.pages.settings.menu.data.description,
      icon: Database,
    },
  ];

  // Only show notifications on native platforms (iOS/Android)
  if (showNotifications) {
    items.push({
      href: "/settings/notifications",
      label: t.pages.settings.menu.notifications.label,
      description: t.pages.settings.menu.notifications.description,
      icon: Bell,
    });
  }

  // Only show admin for admin users (cosmetic - server enforces)
  if (showAdmin) {
    items.push({
      href: "/settings/admin",
      label: t.pages.settings.menu.admin?.label || "Admin",
      description: t.pages.settings.menu.admin?.description || "Administration panel",
      icon: ShieldAlert,
      adminOnly: true,
    });
  }

  return items;
};

export function SettingsNav() {
  const pathname = usePathname();
  const { navigate, pendingPath } = useNavigationFeedback();
  const { t } = useTranslations();
  const [isAdmin, setIsAdmin] = useState(false);

  // Check if we're on a native platform (iOS/Android) for showing notifications menu
  // useSyncExternalStore ensures proper SSR hydration without setState-in-effect
  const showNotifications = useSyncExternalStore(
    // Subscribe is a no-op since platform doesn't change at runtime
    () => () => {},
    // Client snapshot: check platform
    () => isNativePlatform(),
    // Server snapshot: always false (no notifications menu in SSR)
    () => false
  );

  // Check admin status from JWT (cosmetic only - server enforces)
  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      setIsAdmin(data.user?.app_metadata?.role === "admin");
    });
  }, []);

  const settingsItems = getSettingsItems(t, showNotifications, isAdmin);

  // Extract locale from current pathname
  const localeMatch = pathname.match(/^\/(en|no)/);
  const locale = localeMatch ? localeMatch[1] : defaultLocale;

  // Normalize pathname to remove locale prefix for comparison
  // Handle both with and without trailing slash
  const normalizedPath = pathname.replace(/^\/(en|no)/, "").replace(/\/$/, "");
  const normalizedPendingPath = pendingPath?.replace(/^\/(en|no)/, "").replace(/\/$/, "") ?? null;

  const handleItemClick =
    (href: string) => (event: MouseEvent<HTMLAnchorElement>) => {
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
      // Include locale in navigation
      navigate(`/${locale}${href}`);
    };

  return (
    <Card className="p-6">
      <div className="space-y-1">
        <h2 className="text-lg font-semibold text-text-primary">
          {t.pages.settings.title}
        </h2>
        <p className="text-sm text-text-secondary">
          {t.pages.settings.subtitle}
        </p>
      </div>

      <Separator className="my-6" />

      <nav className="space-y-1">
        {settingsItems.map((item) => {
          const Icon = item.icon;
          const isActive = normalizedPath === item.href;
          const isNavigating = normalizedPendingPath === item.href;
          // Show active state if currently on this page OR navigating to it
          const showAsActive = isActive || isNavigating;

          return (
            <Link
              key={item.href}
              href={`/${locale}${item.href}`}
              onClick={handleItemClick(item.href)}
              className={cn(
                "flex items-center gap-3 px-3 py-2.5 rounded-lg transition-colors relative",
                showAsActive
                  ? "bg-surface-secondary text-text-primary font-medium"
                  : "text-text-secondary hover:bg-surface-secondary/50 hover:text-text-primary"
              )}
            >
              <Icon className="h-5 w-5 shrink-0" />
              <span className="flex-1 text-sm">{item.label}</span>
              {isNavigating ? (
                <Loader2 className="h-4 w-4 shrink-0 animate-spin" />
              ) : (
                <ChevronRight className="h-4 w-4 shrink-0 text-text-muted" />
              )}
            </Link>
          );
        })}
      </nav>
    </Card>
  );
}
