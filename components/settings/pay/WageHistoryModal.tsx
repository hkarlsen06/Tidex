'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@appui/Dialog';
import { Button } from '@appui/Button';
import { Input } from '@appui/Input';
import { Label } from '@appui/Label';
import { SupplementsEditor, SupplementsData } from '@/components/settings/SupplementsEditor';
import { WageSourceCard } from '@/components/settings/pay/WageSourceCard';
import { PRESET_WAGE_RATES, PRESET_SUPPLEMENT_RULES } from '@/lib/payroll';
import { IconCalendar, IconAlertTriangle } from '@tabler/icons-react';
import {
  createWageSnapshotAction,
  updateWageSnapshotAction,
  deleteWageSnapshotAction,
} from '@/app/[locale]/(app)/settings/pay/_actions/wage-snapshots';
import type { WageSnapshot, SupplementRule } from '@/data-access/wage-snapshots';

interface WageHistoryModalProps {
  isOpen: boolean;
  onClose: () => void;
  snapshot?: WageSnapshot | null; // If provided, edit mode; otherwise create mode
  mode: 'create' | 'edit' | 'delete' | 'view';
}

const TARIFF_SUPPLEMENTS_DATA: SupplementsData = {
  rules: PRESET_SUPPLEMENT_RULES.map((rule) => ({ ...rule })),
};

export function WageHistoryModal({
  isOpen,
  onClose,
  snapshot,
  mode,
}: WageHistoryModalProps) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  // Form state
  const [fromDate, setFromDate] = useState(() =>
    snapshot ? snapshot.from_date : new Date().toISOString().split('T')[0]
  );
  const [usePreset, setUsePreset] = useState(() =>
    snapshot ? snapshot.wage_level !== null : true
  );
  const [wageLevel, setWageLevel] = useState(() =>
    snapshot ? snapshot.wage_level?.toString() || '1' : '1'
  );
  const [customWage, setCustomWage] = useState(() =>
    snapshot ? snapshot.hourly_wage.toString() : '200'
  );
  const [customSupplements, setCustomSupplements] = useState<SupplementsData | null>(() =>
    snapshot && snapshot.supplements && snapshot.supplements.rules.length > 0
      ? snapshot.supplements
      : null
  );
  const [affectedShiftCount, setAffectedShiftCount] = useState<number | null>(null);

  const handleClose = () => {
    // Reset form state when closing
    setFromDate('');
    setUsePreset(true);
    setWageLevel('1');
    setCustomWage('200');
    setCustomSupplements(null);
    setError(null);
    setAffectedShiftCount(null);
    onClose();
  };

  const handleSave = () => {
    setError(null);

    // Validation
    if (!fromDate) {
      setError('Dato er påkrevd');
      return;
    }

    const wage = usePreset
      ? PRESET_WAGE_RATES[wageLevel]
      : parseFloat(customWage);

    if (!wage || wage <= 0) {
      setError('Ugyldig timelønn');
      return;
    }

    startTransition(async () => {
      try {
        // Convert SupplementsData to payroll SupplementRule format
        // SupplementsData has Omit<SupplementRule, 'id'> with string times and optional 'mode'
        // We need to strip 'mode' and ensure from/to are valid HH:MM format
        const convertSupplements = (
          supplementsData: SupplementsData | null
        ): { rules: SupplementRule[] } => {
          if (!supplementsData || !supplementsData.rules) {
            return { rules: [] };
          }

          const cleanedRules: SupplementRule[] = supplementsData.rules.map((rule) => {
            // Remove 'mode' field and ensure proper types
            const { mode: _mode, ...rest } = rule as any;
            return {
              days: rest.days,
              from: rest.from as `${number}:${number}`, // Type assertion for HHMM
              to: rest.to as `${number}:${number}`,     // Type assertion for HHMM
              ...(rest.rate !== undefined && { rate: rest.rate }),
              ...(rest.percent !== undefined && { percent: rest.percent }),
            };
          });

          return { rules: cleanedRules };
        };

        const data = {
          from_date: fromDate,
          hourly_wage: wage,
          wage_level: usePreset ? parseInt(wageLevel) : null,
          supplements: usePreset
            ? convertSupplements(TARIFF_SUPPLEMENTS_DATA)
            : convertSupplements(customSupplements),
        };

        const result =
          mode === 'edit' && snapshot
            ? await updateWageSnapshotAction(snapshot.id, data)
            : await createWageSnapshotAction(data);

        if ('error' in result) {
          setError(result.error);
          return;
        }

        router.refresh();
        handleClose();
      } catch (err) {
        console.error('Failed to save wage snapshot:', err);
        setError('En uventet feil oppstod');
      }
    });
  };

  const handleDelete = () => {
    if (!snapshot) return;

    setError(null);

    startTransition(async () => {
      try {
        const result = await deleteWageSnapshotAction(snapshot.id);

        if ('error' in result) {
          setError(result.error);
          return;
        }

        setAffectedShiftCount(result.affectedShiftCount);

        // Close after showing affected count briefly
        setTimeout(() => {
          router.refresh();
          handleClose();
        }, 1500);
      } catch (err) {
        console.error('Failed to delete wage snapshot:', err);
        setError('En uventet feil oppstod');
      }
    });
  };

  // Delete confirmation dialog
  if (mode === 'delete' && snapshot) {
    return (
      <Dialog open={isOpen} onOpenChange={(open) => !open && !pending && handleClose()}>
        <DialogContent className="sm:max-w-[425px]">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-destructive">
              <IconAlertTriangle className="h-5 w-5" />
              Slett lønnsoppføring
            </DialogTitle>
            <DialogDescription>
              Er du sikker på at du vil slette lønnsoppføringen fra{' '}
              <strong>{new Date(snapshot.from_date + 'T00:00:00').toLocaleDateString('no-NO')}</strong>?
            </DialogDescription>
          </DialogHeader>

          {affectedShiftCount !== null && (
            <div className="rounded-md bg-blue-50 dark:bg-blue-900/10 p-3">
              <p className="text-sm text-blue-800 dark:text-blue-200">
                {affectedShiftCount === 0
                  ? 'Ingen skift vil bli påvirket.'
                  : `${affectedShiftCount} skift vil bruke en annen lønnsoppføring.`}
              </p>
            </div>
          )}

          {error && (
            <div className="rounded-md bg-red-50 dark:bg-red-900/10 p-3">
              <p className="text-sm text-red-800 dark:text-red-200">{error}</p>
            </div>
          )}

          <DialogFooter>
            <Button variant="outline" onClick={handleClose} disabled={pending}>
              Avbryt
            </Button>
            <Button variant="destructive" onClick={handleDelete} disabled={pending}>
              {pending ? 'Sletter...' : 'Slett'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    );
  }

  // View-only dialog
  if (mode === 'view' && snapshot) {
    return (
      <Dialog open={isOpen} onOpenChange={(open) => !open && handleClose()}>
        <DialogContent className="sm:max-w-[600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <IconCalendar className="h-5 w-5 text-text-muted" />
              Nåværende lønnsinnstillinger
            </DialogTitle>
            <DialogDescription>
              Gyldig fra {new Date(snapshot.from_date + 'T00:00:00').toLocaleDateString('no-NO')}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-6 py-4">
            <WageSourceCard
              usePreset={snapshot.wage_level !== null}
              setUsePreset={() => {}}
              wageLevel={snapshot.wage_level?.toString() || '1'}
              setWageLevel={() => {}}
              customWage={snapshot.hourly_wage.toString()}
              setCustomWage={() => {}}
              disabled={true}
              showCurrentWage={false}
              labels={{
                tariffButton: 'Tariff',
                customButton: 'Egendefinert',
                wageLevelLabel: 'Tariffsteg',
                customWageLabel: 'Egendefinert timelønn (kr)',
                wageLevelPrefix: 'Steg',
                wageLevelUnder16: 'Under 16 år',
                wageLevel16to18: '16-18 år',
                perHour: 'kr/time',
              }}
            />

            {/* Supplements */}
            <div className="space-y-4">
              <div>
                <h3 className="text-sm font-semibold">Tillegg</h3>
                <p className="text-sm text-text-secondary mt-1">
                  {snapshot.wage_level !== null
                    ? 'Tariffavtalens tillegg'
                    : 'Egendefinerte tillegg'}
                </p>
              </div>

              <SupplementsEditor
                value={snapshot.supplements && snapshot.supplements.rules.length > 0
                  ? snapshot.supplements
                  : (snapshot.wage_level !== null ? TARIFF_SUPPLEMENTS_DATA : null)}
                onChange={() => {}}
                readOnly={true}
              />
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={handleClose}>
              Lukk
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    );
  }

  // Create/Edit dialog
  const title = mode === 'edit' ? 'Rediger lønnsoppføring' : 'Ny lønnsoppføring';
  const description =
    mode === 'edit'
      ? 'Endre historisk lønnsinnstilling. Dette vil påvirke beregningen av eksisterende skift på eller etter denne datoen.'
      : 'Legg til en historisk lønnsinnstilling. Bruk dette for å rette opp lønnshistorikken din.';

  const customWageValue = parseFloat(customWage);
  const isCustomWageInvalid =
    !usePreset &&
    (!customWage || Number.isNaN(customWageValue) || customWageValue < 1 || customWageValue > 10000);

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && !pending && handleClose()}>
      <DialogContent className="sm:max-w-[600px] max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <IconCalendar className="h-5 w-5 text-text-muted" />
            {title}
          </DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>

        <div className="space-y-6 py-4">
          {/* Date input */}
          <div className="space-y-2">
            <Label htmlFor="fromDate">Gyldig fra dato</Label>
            <Input
              id="fromDate"
              type="date"
              value={fromDate}
              onChange={(e) => setFromDate(e.target.value)}
              disabled={pending}
            />
            <p className="text-xs text-text-secondary">
              Skift på eller etter denne datoen vil bruke denne lønnsinnstillingen
            </p>
          </div>

          <WageSourceCard
            usePreset={usePreset}
            setUsePreset={setUsePreset}
            wageLevel={wageLevel}
            setWageLevel={setWageLevel}
            customWage={customWage}
            setCustomWage={setCustomWage}
            disabled={pending}
            showCurrentWage={false}
            labels={{
              tariffButton: 'Tariff',
              customButton: 'Egendefinert',
              wageLevelLabel: 'Tariffsteg',
              customWageLabel: 'Egendefinert timelønn (kr)',
              wageLevelPrefix: 'Steg',
              wageLevelUnder16: 'Under 16 år',
              wageLevel16to18: '16-18 år',
              perHour: 'kr/time',
            }}
          />

          {/* Supplements */}
          <div className="space-y-4">
            <div>
              <h3 className="text-sm font-semibold">Tillegg</h3>
              <p className="text-sm text-text-secondary mt-1">
                {usePreset
                  ? 'Tariffavtalens tillegg brukes automatisk'
                  : 'Konfigurer egne tillegg for denne perioden'}
              </p>
            </div>

            <SupplementsEditor
              key={usePreset ? 'tariff' : 'custom'}
              value={usePreset ? TARIFF_SUPPLEMENTS_DATA : customSupplements}
              onChange={setCustomSupplements}
              readOnly={usePreset}
            />
          </div>

          {error && (
            <div className="rounded-md bg-red-50 dark:bg-red-900/10 p-3">
              <p className="text-sm text-red-800 dark:text-red-200">{error}</p>
            </div>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={handleClose} disabled={pending}>
            Avbryt
          </Button>
          <Button onClick={handleSave} disabled={pending || isCustomWageInvalid}>
            {pending ? 'Lagrer...' : mode === 'edit' ? 'Lagre endringer' : 'Opprett'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
