'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { MouseEvent } from 'react';
import { motion } from 'framer-motion';
import { Card } from '@/components/app/Card';
import { ChevronRight, User, Banknote, Palette, Database, CreditCard, Shield, Loader2 } from 'lucide-react';
import { useNavigationFeedback } from '@/components/app/navigation-feedback';
import { useTranslations } from '@/lib/i18n/client';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';
import { defaultLocale } from '@/lib/i18n/config';
import { ScrollablePageWrapper } from '@/components/app/ScrollablePageWrapper';

// Animation variants for staggered page sections
const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.1,
      delayChildren: 0.05,
    },
  },
};

const itemVariants = {
  hidden: { opacity: 0, y: 20 },
  visible: {
    opacity: 1,
    y: 0,
    transition: {
      type: "spring" as const,
      stiffness: 300,
      damping: 30,
    },
  },
};

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
    <ScrollablePageWrapper routeKey="settings">
      <motion.div
        className="py-8"
        variants={containerVariants}
        initial="hidden"
        animate="visible"
      >
        <motion.div variants={itemVariants}>
          <h1 className="text-3xl font-bold mb-2">{t.pages.settings.title}</h1>
          <p className="text-text-secondary mb-10">
            {t.pages.settings.subtitle}
          </p>
        </motion.div>

        <div className="flex flex-col gap-6">
          {settingsItems.map((item) => {
            const Icon = item.icon;
            const isNavigating = normalizedPendingPath === item.href;
            return (
              <motion.div key={item.href} variants={itemVariants}>
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
              </motion.div>
            );
          })}
        </div>
      </motion.div>
    </ScrollablePageWrapper>
  );
}
