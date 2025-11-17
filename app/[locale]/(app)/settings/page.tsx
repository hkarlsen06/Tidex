'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { MouseEvent } from 'react';
import { Card } from '@/components/app/Card';
import { ChevronRight, User, Banknote, Palette, Database, CreditCard, Loader2 } from 'lucide-react';
import { useNavigationFeedback } from '@/components/app/navigation-feedback';
import { useTranslations } from '@/lib/i18n/client';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { defaultLocale } from '@/lib/i18n/config';

const getSettingsItems = (t: Dictionary) => [
  {
    href: '/settings/profile',
    label: t.pages.settings.menu.profile.label,
    description: t.pages.settings.menu.profile.description,
    icon: User,
  },
  {
    href: '/settings/pay',
    label: t.pages.settings.menu.pay.label,
    description: t.pages.settings.menu.pay.description,
    icon: Banknote,
  },
  {
    href: '/settings/subscription',
    label: t.pages.settings.menu.subscription.label,
    description: t.pages.settings.menu.subscription.description,
    icon: CreditCard,
  },
  {
    href: '/settings/display',
    label: t.pages.settings.menu.display.label,
    description: t.pages.settings.menu.display.description,
    icon: Palette,
  },
  {
    href: '/settings/data',
    label: t.pages.settings.menu.data.label,
    description: t.pages.settings.menu.data.description,
    icon: Database,
  },
];

export default function SettingsPage() {
  const pathname = usePathname();
  const { navigate, pendingPath } = useNavigationFeedback();
  const { t } = useTranslations();
  const settingsItems = getSettingsItems(t);

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
    <div className="container mx-auto py-8 max-w-2xl">
      <h1 className="text-3xl font-bold mb-2">{t.pages.settings.title}</h1>
      <p className="text-text-secondary mb-10">
        {t.pages.settings.subtitle}
      </p>

      <div className="flex flex-col gap-6">
        {settingsItems.map((item) => {
          const Icon = item.icon;
          const isNavigating = normalizedPendingPath === item.href;
          return (
            <Link key={item.href} href={`/${locale}${item.href}`} onClick={handleItemClick(item.href)}>
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
          );
        })}
      </div>
    </div>
  );
}
