'use client';

import { useState, useEffect, useSyncExternalStore } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { MouseEvent } from 'react';
import { Card } from '@/components/app/Card';
import { ChevronRight, User, Banknote, Palette, Database, CreditCard, Shield, Bell, Loader2, ShieldAlert, MessageSquare } from 'lucide-react';
import { LegalLinks } from '@/components/settings/subscription/LegalLinks';
import { useNavigationFeedback } from '@/components/app/navigation-feedback';
import { useTranslations } from '@/lib/i18n/client';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { defaultLocale } from '@/lib/i18n/config';
import { ScrollablePageWrapper } from '@/components/app/ScrollablePageWrapper';
import { isNativePlatform } from '@/lib/capacitor/platform';
import { supabase } from '@/lib/supabase/browser';

interface SettingsItem {
  href: string;
  label: string;
  description: string;
  icon: typeof User;
  nativeOnly?: boolean;
  adminOnly?: boolean;
}

const getSettingsItems = (t: Dictionary): SettingsItem[] => [
  // Account & Security group
  {
    href: '/settings/profile',
    label: t.pages.settings.menu.profile.label,
    description: t.pages.settings.menu.profile.description,
    icon: User,
  },
  {
    href: '/settings/security',
    label: t.pages.settings.menu.security.label,
    description: t.pages.settings.menu.security.description,
    icon: Shield,
  },
  {
    href: '/settings/subscription',
    label: t.pages.settings.menu.subscription.label,
    description: t.pages.settings.menu.subscription.description,
    icon: CreditCard,
  },
  // Preferences group
  {
    href: '/settings/notifications',
    label: t.pages.settings.menu.notifications.label,
    description: t.pages.settings.menu.notifications.description,
    icon: Bell,
    nativeOnly: true,
  },
  {
    href: '/settings/display',
    label: t.pages.settings.menu.display.label,
    description: t.pages.settings.menu.display.description,
    icon: Palette,
  },
  // App-specific settings
  {
    href: '/settings/pay',
    label: t.pages.settings.menu.pay.label,
    description: t.pages.settings.menu.pay.description,
    icon: Banknote,
  },
  // Data & Support group
  {
    href: '/settings/data',
    label: t.pages.settings.menu.data.label,
    description: t.pages.settings.menu.data.description,
    icon: Database,
  },
  {
    href: '/settings/feedback',
    label: t.pages.settings.menu.feedback?.label || 'Feedback',
    description: t.pages.settings.menu.feedback?.description || 'Send us your feedback',
    icon: MessageSquare,
  },
  // Admin (always last)
  {
    href: '/settings/admin',
    label: t.pages.settings.menu.admin?.label || 'Admin',
    description: t.pages.settings.menu.admin?.description || 'Administration panel',
    icon: ShieldAlert,
    adminOnly: true,
  },
];

export default function SettingsPage() {
  const pathname = usePathname();
  const { navigate, pendingPath } = useNavigationFeedback();
  const { t } = useTranslations();
  const [isAdmin, setIsAdmin] = useState(false);

  // Check if we're on a native platform (iOS/Android) for showing notifications menu
  // useSyncExternalStore ensures proper SSR hydration without setState-in-effect
  const isNative = useSyncExternalStore(
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
      setIsAdmin(data.user?.app_metadata?.role === 'admin');
    });
  }, []);

  const allItems = getSettingsItems(t);
  const settingsItems = allItems.filter(item =>
    (!item.nativeOnly || isNative) && (!item.adminOnly || isAdmin)
  );

  // Extract locale from current pathname
  const localeMatch = pathname.match(/^\/(en|no|de)/);
  const locale = localeMatch ? localeMatch[1] : defaultLocale;

  // Normalize pending path for comparison
  const normalizedPendingPath = pendingPath?.replace(/^\/(en|no|de)/, "").replace(/\/$/, "") ?? null;

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
    // Include locale in navigation
    navigate(`/${locale}${href}`);
  };

  return (
    <ScrollablePageWrapper routeKey="settings">
      <div className="py-8">
        <div>
          <h1 className="text-3xl font-bold mb-2">{t.pages.settings.title}</h1>
          <p className="text-text-secondary mb-10">
            {t.pages.settings.subtitle}
          </p>
        </div>

        <div className="flex flex-col gap-6">
          {settingsItems.map((item) => {
            const Icon = item.icon;
            const isNavigating = normalizedPendingPath === item.href;
            return (
              <div key={item.href}>
                <Link href={`/${locale}${item.href}`} onClick={handleItemClick(item.href)}>
                  <Card className="p-5 hover:bg-surface-secondary/50 transition-colors cursor-pointer">
                    <div className="flex items-center gap-4">
                      <div className="p-3 rounded-lg bg-surface-secondary">
                        <Icon className="h-6 w-6 text-text-primary" />
                      </div>
                      <div className="flex-1">
                        <h3 className="font-semibold text-lg text-text-primary mb-0.5">{item.label}</h3>
                        <p className="text-sm text-text-secondary">{item.description}</p>
                      </div>
                      {isNavigating ? (
                        <Loader2 className="h-5 w-5 text-text-secondary shrink-0 animate-spin" />
                      ) : (
                        <ChevronRight className="h-5 w-5 text-text-secondary shrink-0" />
                      )}
                    </div>
                  </Card>
                </Link>
              </div>
            );
          })}
        </div>

        {/* Footer with legal links and copyright */}
        <div className="mt-12 pt-4 border-t border-border-subtle flex flex-wrap items-center justify-between gap-x-4 gap-y-2 text-sm">
          <LegalLinks className="" />
          <span className="text-text-muted">© 2025 Tidex</span>
        </div>
      </div>
    </ScrollablePageWrapper>
  );
}
