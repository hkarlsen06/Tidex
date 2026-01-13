import { Gift } from 'lucide-react';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface FreeTrialBadgeProps {
  durationDays: number;
  t: Dictionary;
}

export function FreeTrialBadge({ durationDays, t }: FreeTrialBadgeProps) {
  const label = t.pages.settings.subscription.upgradePlans.iap.freeTrialBadge.replace(
    '{days}',
    String(durationDays)
  );

  return (
    <div className="inline-flex items-center bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400 px-2 py-1 rounded-md text-xs font-medium">
      <Gift className="h-3 w-3 mr-1" />
      {label}
    </div>
  );
}
