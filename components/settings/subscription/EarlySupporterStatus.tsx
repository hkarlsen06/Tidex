'use client';

import { Card } from '@/components/app/Card';
import { Badge } from '@/components/app/Badge';
import { Separator } from '@/components/app/Separator';
import { Heart } from 'lucide-react';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface EarlySupporterStatusProps {
  t: Dictionary;
}

export function EarlySupporterStatus({ t }: EarlySupporterStatusProps) {
  return (
    <Card className="p-6 border-2 border-text-primary bg-gradient-to-br from-surface-primary to-surface-secondary">
      <div className="space-y-6">
        <div className="flex items-start justify-between">
          <div className="flex items-start gap-3">
            <div className="p-3 rounded-full bg-red-500/10 dark:bg-red-500/20">
              <Heart className="h-6 w-6 text-red-600 dark:text-red-500 fill-current" />
            </div>
            <div>
              <h3 className="text-lg font-semibold">{t.pages.settings.subscription.earlySupporter.title}</h3>
              <p className="text-sm text-text-secondary mt-1">
                {t.pages.settings.subscription.earlySupporter.subtitle}
              </p>
            </div>
          </div>
          <Badge variant="default">{t.pages.settings.subscription.earlySupporter.badgeFree}</Badge>
        </div>

        <Separator />

        <div className="p-4 bg-surface-secondary rounded-lg">
          <p className="text-sm text-text-secondary mb-4">
            {t.pages.settings.subscription.earlySupporter.description}
          </p>

          <h4 className="font-semibold mb-2">{t.pages.settings.subscription.earlySupporter.featuresTitle}</h4>
          <ul className="space-y-1 text-sm text-text-secondary">
            {t.pages.settings.subscription.earlySupporter.features.map((feature, i) => (
              <li key={i}>✓ {feature}</li>
            ))}
          </ul>
        </div>

        <div className="flex items-center gap-2 p-3 bg-surface-primary rounded-lg border border-border-subtle">
          <div className="text-2xl">✰</div>
          <div className="flex-1">
            <p className="text-sm font-medium">{t.pages.settings.subscription.earlySupporter.savingsTitle}</p>
            <p className="text-xs text-text-secondary">{t.pages.settings.subscription.earlySupporter.savingsValue}</p>
          </div>
        </div>
      </div>
    </Card>
  );
}
