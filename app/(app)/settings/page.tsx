'use client';

import Link from 'next/link';
import type { MouseEvent } from 'react';
import { Card } from '@appui/Card';
import { ChevronRight, User, Banknote, Palette, Database, CreditCard, Loader2 } from 'lucide-react';
import { useNavigationFeedback } from '@/components/app/navigation-feedback';

const settingsItems = [
  {
    href: '/settings/profile',
    label: 'Profil',
    description: 'Administrer din personlige informasjon',
    icon: User,
  },
  {
    href: '/settings/pay',
    label: 'Lønn og tillegg',
    description: 'Konfigurer lønnsinnstillinger og tillegg',
    icon: Banknote,
  },
  {
    href: '/settings/subscription',
    label: 'Abonnement',
    description: 'Administrer ditt abonnement',
    icon: CreditCard,
  },
  {
    href: '/settings/display',
    label: 'Utseende',
    description: 'Tilpass hvordan appen ser ut',
    icon: Palette,
  },
  {
    href: '/settings/data',
    label: 'Data',
    description: 'Eksporter dine data som PDF',
    icon: Database,
  },
];

export default function SettingsPage() {
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

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      <h1 className="text-3xl font-bold mb-2">Innstillinger</h1>
      <p className="text-text-secondary mb-10">
        Administrer dine innstillinger og preferanser
      </p>

      <div className="flex flex-col gap-6">
        {settingsItems.map((item) => {
          const Icon = item.icon;
          const isNavigating = pendingPath === item.href;
          return (
            <Link key={item.href} href={item.href} onClick={handleItemClick(item.href)}>
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
                    <Loader2 className="h-5 w-5 text-text-secondary flex-shrink-0 animate-spin" />
                  ) : (
                    <ChevronRight className="h-5 w-5 text-text-secondary flex-shrink-0" />
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
