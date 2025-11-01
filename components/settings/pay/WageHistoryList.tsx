'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import { IconPlus, IconHistory, IconClock, IconCoins } from '@tabler/icons-react';
import { formatCurrency } from '@/lib/formatters';
import { WageHistoryModal } from './WageHistoryModal';
import type { WageSnapshot } from '@/data-access/wage-snapshots';
import type { Dictionary } from '@/lib/i18n/dictionaries/no';

// Preset wage rates removed - no longer needed in this component

interface WageHistoryListProps {
  snapshots: WageSnapshot[];
  t: Dictionary;
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

/**
 * Get wage level label
 */
function getWageLevelLabel(wageLevel: number | null): string {
  if (wageLevel === null) return 'Egendefinert lønn';
  if (wageLevel === -1) return 'Ungdomstariff (-1)';
  if (wageLevel === -2) return 'Ungdomstariff (-2)';
  return `Tariffsteg ${wageLevel}`;
}

export function WageHistoryList({
  snapshots,
}: Omit<WageHistoryListProps, 't'>) {
  const [modalOpen, setModalOpen] = useState(false);
  const [modalMode, setModalMode] = useState<'create' | 'edit' | 'delete'>('create');
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

  const handleDelete = (snapshot: WageSnapshot) => {
    setSelectedSnapshot(snapshot);
    setModalMode('delete');
    setModalOpen(true);
  };

  const handleCloseModal = () => {
    setModalOpen(false);
    setSelectedSnapshot(null);
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-text-primary flex items-center gap-2">
            <IconHistory className="h-5 w-5" />
            Lønnshistorikk
          </h3>
          <p className="text-sm text-text-secondary mt-1">
            Historiske lønnsendringer som brukes for å beregne tidligere skift korrekt
          </p>
        </div>
        <Button onClick={handleAddNew} size="sm">
          <IconPlus className="h-4 w-4 mr-2" />
          Ny oppføring
        </Button>
      </div>

      {/* List */}
      {snapshots.length === 0 ? (
        <Card className="p-8">
          <div className="text-center">
            <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-surface-secondary mb-4">
              <IconHistory className="h-6 w-6 text-text-secondary" />
            </div>
            <h4 className="font-medium text-text-primary mb-2">Ingen lønnshistorikk</h4>
            <p className="text-sm text-text-secondary mb-4">
              Lønnshistorikk opprettes automatisk når du endrer lønnsinnstillingene dine.
            </p>
            <Button onClick={handleAddNew} variant="outline">
              <IconPlus className="h-4 w-4 mr-2" />
              Legg til historisk lønnsoppføring
            </Button>
          </div>
        </Card>
      ) : (
        <div className="space-y-3">
          {snapshots.map((snapshot, index) => {
            const isLatest = index === 0;
            const nextSnapshot = snapshots[index + 1] ?? null;

            return (
              <Card
                key={snapshot.id}
                className={`p-4 ${isLatest ? 'ring-2 ring-brand-primary' : ''}`}
              >
                <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  {/* Left side: Date and wage info */}
                  <div className="flex-1 space-y-3">
                    <div className="flex items-start gap-3">
                      <div className="p-2 rounded-lg bg-surface-secondary flex-shrink-0">
                        <IconClock className="h-5 w-5 text-text-primary" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <h4 className="font-semibold text-text-primary">
                            {snapshot.from_date === null
                              ? 'Grunntariff'
                              : formatDate(snapshot.from_date)}
                          </h4>
                          {isLatest && (
                            <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-brand-primary text-white">
                              Gjeldende
                            </span>
                          )}
                        </div>
                        <p className="text-xs text-text-secondary mt-0.5">
                          {snapshot.from_date === null
                            ? 'Gjelder for alle datoer uten spesifikk endring'
                            : nextSnapshot && nextSnapshot.from_date !== null
                            ? `Gyldig fra ${formatDate(snapshot.from_date)} til ${formatDate(nextSnapshot.from_date)}`
                            : `Gyldig fra ${formatDate(snapshot.from_date)}`}
                        </p>
                      </div>
                    </div>

                    {/* Wage details */}
                    <div className="flex items-start gap-3">
                      <div className="p-2 rounded-lg bg-surface-secondary flex-shrink-0">
                        <IconCoins className="h-5 w-5 text-text-primary" />
                      </div>
                      <div className="flex-1">
                        <div className="flex items-baseline gap-2">
                          <span className="text-lg font-bold text-text-primary">
                            {formatCurrency(snapshot.hourly_wage)}
                          </span>
                          <span className="text-sm text-text-secondary">kr/time</span>
                        </div>
                        <p className="text-sm text-text-secondary mt-0.5">
                          {getWageLevelLabel(snapshot.wage_level)}
                        </p>
                        {snapshot.supplements?.rules?.length > 0 && (
                          <p className="text-xs text-text-muted mt-1">
                            {snapshot.supplements.rules.length} tillegg konfigurert
                          </p>
                        )}
                      </div>
                    </div>
                  </div>

                  {/* Right side: Actions */}
                  <div className="flex gap-2 sm:flex-col sm:items-end">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleEdit(snapshot)}
                      className="flex-1 sm:flex-none"
                    >
                      Rediger
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleDelete(snapshot)}
                      className="flex-1 sm:flex-none text-destructive hover:text-destructive"
                    >
                      Slett
                    </Button>
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      )}

      {/* Info message */}
      {snapshots.length > 0 && (
        <div className="rounded-md bg-blue-50 dark:bg-blue-900/10 p-4">
          <p className="text-sm text-blue-800 dark:text-blue-200">
            <strong>Tips:</strong> Skift bruker automatisk lønnsinnstillingene som var
            gjeldende på skiftets dato. Dette sikrer at historiske skift beregnes med
            riktig lønn, selv om du har endret lønnen senere.
          </p>
        </div>
      )}

      {/* Modal */}
      <WageHistoryModal
        key={selectedSnapshot?.id || 'new'}
        isOpen={modalOpen}
        onClose={handleCloseModal}
        snapshot={selectedSnapshot}
        mode={modalMode}
      />
    </div>
  );
}
