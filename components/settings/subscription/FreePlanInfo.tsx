'use client';

import { Card } from '@/components/app/Card';
import { AlertCircle } from 'lucide-react';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface FreePlanInfoProps {
  t: Dictionary;
}

export function FreePlanInfo({ t }: FreePlanInfoProps) {
  return (
    <Card className="p-6 border-border-subtle bg-surface-secondary/50">
      <div className="flex gap-3">
        <AlertCircle className="h-5 w-5 text-text-secondary flex-shrink-0 mt-0.5" />
        <div>
          <h4 className="font-semibold text-sm mb-1">{t.pages.settings.subscription.freePlan.title}</h4>
          <p className="text-sm text-text-secondary">
            {t.pages.settings.subscription.freePlan.description}
          </p>
        </div>
      </div>
    </Card>
  );
}
