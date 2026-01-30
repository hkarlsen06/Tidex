'use client';

import { useState } from 'react';
import { Card } from '@/components/app/Card';
import { Button } from '@/components/app/Button';
import { Plus, History, Pencil } from 'lucide-react';
import { WageHistoryModal } from './WageHistoryModal';
import type { WageSnapshot } from '@/data-access/wage-snapshots';
import type { TariffVersion } from '@/data-access/tariff';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

// Preset wage rates removed - no longer needed in this component

interface WageHistoryListProps {
  snapshots: WageSnapshot[];
  t: Dictionary;
  /**
   * Initial tariff version to use when creating new snapshots.
   * If not provided, the modal will fetch the latest version when opened.
   */
  initialTariffVersion?: TariffVersion | null;
}

/**
 * Format date for display
 */
function formatDate(isoDate: string): string {
  const date = new Date(isoDate + 'T00:00:00');
  return date.toLocaleDateString('no-NO', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
}


export function WageHistoryList({
  snapshots,
  t,
  initialTariffVersion,
}: WageHistoryListProps) {
  const [modalOpen, setModalOpen] = useState(false);
  const [modalMode, setModalMode] = useState<'create' | 'edit'>('create');
  const [selectedSnapshot, setSelectedSnapshot] = useState<WageSnapshot | null>(null);

  const handleAddNew = () => {
    setSelectedSnapshot(null);
    setModalMode('create');
    setModalOpen(true);
  };

  const handleEdit = (snapshot: WageSnapshot) => {
    setSelectedSnapshot(snapshot);
    setModalMode('edit');
    setModalOpen(true);
  };

  const handleCloseModal = () => {
    setModalOpen(false);
    setSelectedSnapshot(null);
  };

  // Filter out the current (most recent) snapshot - it's shown in CurrentWageCard
  const historicalSnapshots = snapshots.slice(1);

  // Check if only baseline exists (snapshots has 1 item with from_date === null)
  const onlyBaselineExists = snapshots.length === 1 && snapshots[0]?.from_date === null;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-text-primary flex items-center gap-2">
            <History className="h-5 w-5" />
            {t.pages.settings.pay.wageHistory.title}
          </h3>
          <p className="text-sm text-text-secondary mt-1">
            {t.pages.settings.pay.wageHistory.subtitle}
          </p>
        </div>
        <Button onClick={handleAddNew} size="sm">
          <Plus className="h-4 w-4 mr-2" />
          {t.pages.settings.pay.wageHistory.addNew}
        </Button>
      </div>

      {/* Only show list when not only baseline */}
      {!onlyBaselineExists && (
        <>
          {/* List */}
          {historicalSnapshots.length === 0 ? (
            <Card className="p-8">
              <div className="text-center">
                <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-surface-secondary mb-4">
                  <History className="h-6 w-6 text-text-secondary" />
                </div>
                <h4 className="font-medium text-text-primary mb-2">{t.pages.settings.pay.wageHistory.emptyTitle}</h4>
                <p className="text-sm text-text-secondary mb-4">
                  {t.pages.settings.pay.wageHistory.emptyDescription}
                </p>
                <Button onClick={handleAddNew} variant="outline">
                  <Plus className="h-4 w-4 mr-2" />
                  {t.pages.settings.pay.wageHistory.addHistorical}
                </Button>
              </div>
            </Card>
          ) : (
            <Card className="divide-y divide-border">
              {historicalSnapshots.map((snapshot) => {
                const isPreset = snapshot.wage_level !== null;

                return (
                  <div
                    key={snapshot.id}
                    className="p-4"
                  >
                    <div className="flex items-center gap-3">
                      {/* Left content */}
                      <div className="flex-1 min-w-0 space-y-2">
                        {/* Date - prominent */}
                        <div className="text-lg font-semibold text-text-primary">
                          {snapshot.from_date === null
                            ? t.pages.settings.pay.wageHistory.baseline
                            : formatDate(snapshot.from_date)}
                        </div>

                        {/* Wage and details */}
                        <div className="flex items-baseline gap-2 flex-wrap text-sm text-text-secondary">
                          <span className="font-medium text-text-primary">
                            {snapshot.hourly_wage.toFixed(2)} kr/time
                          </span>
                          {isPreset && (
                            <span className="text-text-muted">
                              • {t.pages.settings.pay.wage.wageLevelPrefix} {snapshot.wage_level}
                            </span>
                          )}
                        </div>
                      </div>

                      {/* Right button */}
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => handleEdit(snapshot)}
                        className="gap-1 shrink-0"
                      >
                        <Pencil className="h-4 w-4" />
                        <span className="hidden sm:inline">{t.pages.settings.pay.wageHistory.edit}</span>
                      </Button>
                    </div>
                  </div>
                );
              })}
            </Card>
          )}

          {/* Info message */}
          {historicalSnapshots.length > 0 && (
            <div className="rounded-md bg-blue-50 dark:bg-blue-900/10 p-4">
              <p className="text-sm text-blue-800 dark:text-blue-200">
                <strong>Tips:</strong> {t.pages.settings.pay.wageHistory.infoTip}
              </p>
            </div>
          )}
        </>
      )}

      {/* Modal */}
      <WageHistoryModal
        key={selectedSnapshot?.id || 'new'}
        isOpen={modalOpen}
        onClose={handleCloseModal}
        snapshot={selectedSnapshot}
        mode={modalMode}
        t={t}
        locale={t.common.currency === 'kr' ? 'no-NO' : 'en-US'}
        initialTariffVersion={initialTariffVersion}
      />
    </div>
  );
}
