'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import { IconEdit } from '@tabler/icons-react';
import { WageHistoryModal } from './WageHistoryModal';
import type { WageSnapshot } from '@/data-access/wage-snapshots';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

interface CurrentWageCardProps {
  currentSnapshot: WageSnapshot | null;
  t: Dictionary;
}

/**
 * Format date for display
 */
function formatDate(isoDate: string, locale: string = 'no-NO'): string {
  const date = new Date(isoDate + 'T00:00:00');
  return date.toLocaleDateString(locale, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
}

export function CurrentWageCard({ currentSnapshot, t }: CurrentWageCardProps) {
  const [isEditModalOpen, setIsEditModalOpen] = useState(false);

  if (!currentSnapshot) {
    return (
      <Card className="p-6">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-lg font-semibold text-text-secondary">
              {t.pages.settings.pay.currentWageCard.noSettingsTitle}
            </h3>
            <p className="text-sm text-text-secondary mt-1">
              {t.pages.settings.pay.currentWageCard.noSettingsDescription}
            </p>
          </div>
        </div>
      </Card>
    );
  }

  const supplementCount = currentSnapshot.supplements?.rules?.length ?? 0;
  const isPreset = currentSnapshot.wage_level !== null;
  const locale = t.common.currency === 'kr' ? 'no-NO' : 'en-US';

  return (
    <>
      <Card className="p-6 border-2 border-blue-500/30 dark:border-blue-400/30">
        <div className="flex items-center gap-3">
          {/* Left content */}
          <div className="flex-1 min-w-0 space-y-3">
            {/* Wage */}
            <div className="flex items-baseline gap-2 flex-wrap">
              <span className="text-3xl font-bold text-text-primary">
                {currentSnapshot.hourly_wage.toFixed(2)}
              </span>
              <span className="text-sm text-text-secondary">kr/time</span>
              {isPreset && (
                <span className="text-sm text-text-muted">
                  • {t.pages.settings.pay.wage.wageLevelPrefix} {currentSnapshot.wage_level}
                </span>
              )}
            </div>

            {/* Info */}
            <p className="text-xs text-text-secondary max-w-prose">
              {currentSnapshot.from_date === null
                ? t.pages.settings.pay.wageHistory.baselineDescription
                : t.pages.settings.pay.wageHistory.validFrom.replace('{date}', formatDate(currentSnapshot.from_date, locale))}
              {' • '}
              {supplementCount} {supplementCount === 1 ? t.pages.settings.pay.currentWageCard.supplementsSingular : t.pages.settings.pay.currentWageCard.supplementsPlural}
            </p>
          </div>

          {/* Right button */}
          <Button
            variant="outline"
            size="sm"
            onClick={() => setIsEditModalOpen(true)}
            className="gap-2 flex-shrink-0"
          >
            <IconEdit className="h-4 w-4" />
            <span className="hidden sm:inline">{t.pages.settings.pay.wageHistory.edit}</span>
          </Button>
        </div>
      </Card>

      {/* Edit Modal */}
      <WageHistoryModal
        isOpen={isEditModalOpen}
        onClose={() => setIsEditModalOpen(false)}
        snapshot={currentSnapshot}
        mode="edit"
        t={t}
        locale={locale}
      />
    </>
  );
}
