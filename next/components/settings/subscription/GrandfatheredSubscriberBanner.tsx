'use client';

import { Card } from '@/components/app/Card';
import { Heart } from 'lucide-react';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface GrandfatheredSubscriberBannerProps {
  t: Dictionary;
}

export function GrandfatheredSubscriberBanner({ t }: GrandfatheredSubscriberBannerProps) {
  return (
    <Card className="p-6 border-2 border-yellow-500/50 bg-linear-to-br from-yellow-500/5 to-orange-500/5">
      <div className="space-y-4">
        <div className="flex items-center gap-4">
          <div className="p-3 rounded-full bg-red-500/10 dark:bg-red-500/20 shrink-0">
            <Heart className="h-6 w-6 text-red-600 dark:text-red-500 fill-current" />
          </div>
          <div className="flex-1">
            <h3 className="text-lg font-bold">{t.pages.settings.subscription.grandfathered.title}</h3>
          </div>
        </div>
        <p className="text-sm text-text-secondary">
          {t.pages.settings.subscription.grandfathered.message}
        </p>
      </div>
    </Card>
  );
}
