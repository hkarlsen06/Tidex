'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import { IconEye, IconCoins, IconStack2 } from '@tabler/icons-react';
import { WageHistoryModal } from './WageHistoryModal';
import type { WageSnapshot } from '@/data-access/wage-snapshots';

interface CurrentWageCardProps {
  currentSnapshot: WageSnapshot | null;
}

export function CurrentWageCard({ currentSnapshot }: CurrentWageCardProps) {
  const [isViewModalOpen, setIsViewModalOpen] = useState(false);

  if (!currentSnapshot) {
    return (
      <Card className="p-6">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-lg font-semibold text-text-secondary">Ingen lønnsinnstillinger funnet</h3>
            <p className="text-sm text-text-secondary mt-1">
              Opprett en lønnsoppføring nedenfor for å komme i gang
            </p>
          </div>
        </div>
      </Card>
    );
  }

  const supplementCount = currentSnapshot.supplements?.rules?.length ?? 0;
  const isPreset = currentSnapshot.wage_level !== null;

  return (
    <>
      <Card className="p-6">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-6 flex-1">
            {/* Wage Display */}
            <div className="flex items-center gap-3">
              <div className="h-12 w-12 rounded-full bg-brand-gradientStart/10 flex items-center justify-center">
                <IconCoins className="h-6 w-6 text-brand-gradientStart" stroke={2} />
              </div>
              <div>
                <p className="text-sm text-text-secondary">Nåværende timelønn</p>
                <p className="text-2xl font-bold">
                  {currentSnapshot.hourly_wage.toFixed(2)} kr/time
                </p>
                {isPreset && (
                  <p className="text-xs text-text-secondary">
                    Tariffsteg {currentSnapshot.wage_level}
                  </p>
                )}
              </div>
            </div>

            {/* Supplements Count */}
            <div className="flex items-center gap-3 border-l border-border pl-6">
              <div className="h-12 w-12 rounded-full bg-blue-500/10 flex items-center justify-center">
                <IconStack2 className="h-6 w-6 text-blue-500" stroke={2} />
              </div>
              <div>
                <p className="text-sm text-text-secondary">Tillegg</p>
                <p className="text-2xl font-bold">{supplementCount}</p>
                <p className="text-xs text-text-secondary">
                  {supplementCount === 1 ? 'tillegg' : 'tillegg'}
                </p>
              </div>
            </div>
          </div>

          {/* View Button */}
          <Button
            variant="outline"
            size="sm"
            onClick={() => setIsViewModalOpen(true)}
            className="gap-2"
          >
            <IconEye className="h-4 w-4" />
            Vis detaljer
          </Button>
        </div>
      </Card>

      {/* View Modal */}
      <WageHistoryModal
        isOpen={isViewModalOpen}
        onClose={() => setIsViewModalOpen(false)}
        snapshot={currentSnapshot}
        mode="view"
      />
    </>
  );
}
