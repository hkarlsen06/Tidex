"use client";

import { useEffect, useState, useTransition, useRef, useMemo } from "react";
import { useRouter } from "next/navigation";
import { IconPencil, IconTrash, IconClock, IconCheck, IconX, IconRefresh, IconInfoCircle } from "@tabler/icons-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@components/app/Dialog";
import { Button } from "@components/app/Button";
import { Input } from "@components/app/Input";
import type { ShiftWithComputations, UserSettings, SupplementRule } from "@/lib/payroll";
import SupplementBreakdown, { type SupplementSegmentInput } from "./SupplementBreakdown";
import { updateShift } from "@/app/[locale]/(app)/shifts/_actions/updateShift";
import { clearShiftSnapshots } from "@/app/[locale]/(app)/shifts/_actions/clearShiftSnapshots";
import { cn } from "@/lib/cn";
import { TimeInput } from "@/components/app/TimeInput";
import { useTranslations } from "@/lib/i18n/client";
import {
  formatCurrency,
  formatHours as formatHoursValue,
  formatPlainAmount,
} from "@/lib/formatters";
import { getDateFormatter } from "@/lib/i18n/locale";
import { SeriesEditModal } from "./SeriesEditModal";
import type { ExistingShift } from "@/lib/series/conflicts";
import { PRESET_WAGE_RATES } from "@/lib/payroll/calc";

const MINUTES_PER_DAY = 24 * 60;

function minutesToSegmentTime(minutes: number) {
  const dayOffset = Math.floor(minutes / MINUTES_PER_DAY);
  const remainder = ((minutes % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
  const isFullDay = remainder === 0 && minutes !== 0;
  const hours = isFullDay ? 24 : Math.floor(remainder / 60);
  const mins = isFullDay ? 0 : remainder % 60;
  return {
    time: `${String(hours).padStart(2, "0")}:${String(mins).padStart(2, "0")}`,
    dayOffset,
  };
}

function buildSupplementSegments(shift: ShiftWithComputations): SupplementSegmentInput[] {
  // Use originalWagePeriods for display (shows configured time ranges)
  // but calculate actual paid hours from adjusted wagePeriods (after break deduction)
  const original = shift.computed.originalWagePeriods;
  const adjusted = shift.computed.wagePeriods;

  // Group consecutive periods with same supplement rate and calculate actual hours
  const segments: SupplementSegmentInput[] = [];
  let i = 0;

  while (i < original.length) {
    const period = original[i];
    if (period.supplementRate <= 0) {
      i++;
      continue;
    }

    // Find consecutive periods with same supplement rate
    let groupStart = period.fromMin;
    let groupEnd = period.toMin;
    let currentRate = period.supplementRate;
    let j = i + 1;

    while (j < original.length && original[j].supplementRate === currentRate) {
      groupEnd = original[j].toMin;
      j++;
    }

    // Calculate actual paid hours for this supplement rate group from adjusted periods
    let actualHours = 0;
    for (const adj of adjusted) {
      // Find overlap between adjusted period and original group
      if (adj.supplementRate === currentRate) {
        const overlapStart = Math.max(adj.fromMin, groupStart);
        const overlapEnd = Math.min(adj.toMin, groupEnd);
        if (overlapEnd > overlapStart) {
          actualHours += (overlapEnd - overlapStart) / 60;
        }
      }
    }

    const from = minutesToSegmentTime(groupStart);
    const to = minutesToSegmentTime(groupEnd);

    segments.push({
      from: from.time,
      to: to.time,
      dayOffset: from.dayOffset,
      rate: currentRate,
      actualHours,
    });

    i = j;
  }

  return segments;
}

const TIME_PATTERN = /^\d{2}:\d{2}$/;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export type ShiftDetailsProps = {
  isOpen: boolean;
  shift: ShiftWithComputations | null;
  onClose: () => void;
  onDelete?: (shiftId: string | any) => void;
  isDeleting?: boolean;
  existingShifts?: ExistingShift[];
  userSettings?: UserSettings;
  presetRules?: SupplementRule[];
};

function capitalize(input: string) {
  return input.charAt(0).toUpperCase() + input.slice(1);
}

function formatTimeRange(start: string, end: string) {
  return `${start} – ${end}`;
}

function formatHours(value: number) {
  return formatHoursValue(value);
}

function formatCurrencyNOKInt(value: number) {
  return formatCurrency(value);
}

function formatHourlyRate(value: number) {
  return `${formatPlainAmount(value, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })} kr/t`;
}

// Helper to resolve current wage rate from settings
function resolveCurrentWage(settings: UserSettings): number | null {
  if (settings.use_preset && settings.current_wage_level != null) {
    const key = String(settings.current_wage_level);
    return PRESET_WAGE_RATES[key] ?? null;
  }
  if (settings.custom_wage && settings.custom_wage > 0) {
    return settings.custom_wage;
  }
  return null;
}

function compareSupplementRules(rules1: SupplementRule[], rules2: SupplementRule[]): boolean {
  if (rules1.length !== rules2.length) return false;

  // Compare each rule
  for (let i = 0; i < rules1.length; i++) {
    const r1 = rules1[i];
    const r2 = rules2[i];

    // Compare days arrays
    if (r1.days.length !== r2.days.length) return false;
    if (!r1.days.every((day, idx) => day === r2.days[idx])) return false;

    // Compare time ranges
    if (r1.from !== r2.from || r1.to !== r2.to) return false;

    // Compare rate/percent (handle optional fields)
    if (r1.rate !== r2.rate) return false;
    if (r1.percent !== r2.percent) return false;
  }

  return true;
}

export function ShiftDetails({
  isOpen,
  shift,
  onClose,
  onDelete,
  isDeleting,
  existingShifts = [],
  userSettings = {},
  presetRules = [],
}: ShiftDetailsProps) {
  const { t, locale } = useTranslations();
  const router = useRouter();
  const [seriesModalOpen, setSeriesModalOpen] = useState(false);

  // Create locale-aware date formatters
  const dayFormatter = useMemo(() => {
    return getDateFormatter(locale, { weekday: "long" });
  }, [locale]);

  const dateFormatter = useMemo(() => {
    return getDateFormatter(locale, {
      day: "2-digit",
      month: "long",
    });
  }, [locale]);

  const formatDate = useMemo(() => {
    return (dateISO: string) => {
      const d = new Date(`${dateISO}T00:00:00Z`);
      const day = capitalize(dayFormatter.format(d));
      const label = capitalize(dateFormatter.format(d));
      return `${label} · ${day}`;
    };
  }, [dayFormatter, dateFormatter]);
  const [isEditing, setIsEditing] = useState(false);
  const [startTime, setStartTime] = useState("");
  const [endTime, setEndTime] = useState("");
  const [shiftDate, setShiftDate] = useState("");
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saving, startTransition] = useTransition();
  const [clearingSnapshots, startClearingSnapshots] = useTransition();
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const startInputRef = useRef<HTMLInputElement>(null);
  const endInputRef = useRef<HTMLInputElement>(null);

  // Reset form state when shift changes
  // Note: These setState calls are intentional to reset UI state when the shift prop changes
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setIsEditing(false);
    setStartTime(shift?.start_time ?? "");
    setEndTime(shift?.end_time ?? "");
    setShiftDate(shift?.shift_date ?? "");
    setSaveError(null);
    setConfirmingDelete(false);
  }, [shift]);

  const handleEdit = () => {
    if (!shift) return;
    setConfirmingDelete(false);
    setStartTime(shift.start_time);
    setEndTime(shift.end_time);
    setShiftDate(shift.shift_date);
    setIsEditing(true);
  };

  const handleDeleteClick = () => {
    if (!shift) return;
    setIsEditing(false);
    setSaveError(null);
    setConfirmingDelete(true);
  };

  const handleConfirmDelete = () => {
    if (!shift) return;
    setConfirmingDelete(false);

    // If series ghost, pass series info for exclusion handling
    if (shift.series_id) {
      onDelete?.({ shiftId: shift.id, seriesId: shift.series_id, shiftDate: shift.shift_date });
    } else {
      onDelete?.(shift.id);
    }
  };

  const handleEditSeries = () => {
    if (!shift?.series_id) return;
    setSeriesModalOpen(true);
  };

  const handleClearSnapshots = () => {
    if (!shift) return;
    startClearingSnapshots(async () => {
      try {
        await clearShiftSnapshots(shift.id);
        router.refresh();
        onClose();
      } catch (error) {
        console.error("Failed to clear snapshots:", error);
      }
    });
  };

  const handleSave = () => {
    if (!shift) return;
    if (!DATE_PATTERN.test(shiftDate)) {
      setSaveError(t.pages.shifts.details.errorInvalidDate);
      return;
    }
    if (!TIME_PATTERN.test(startTime) || !TIME_PATTERN.test(endTime)) {
      setSaveError(t.pages.shifts.details.errorInvalidTime);
      return;
    }
    setSaveError(null);
    startTransition(async () => {
      try {
        await updateShift({
          id: shift.id,
          shift_date: shiftDate,
          start: startTime,
          end: endTime,
          series_id: shift.series_id, // Pass series_id if present
        });
        setIsEditing(false);
        router.refresh();
      } catch (error: any) {
        setSaveError(error?.message || t.pages.shifts.details.errorUpdate);
      }
    });
  };

  const isSeriesGhost = Boolean(shift?.series_id);

  const supplementSegments = shift ? buildSupplementSegments(shift) : [];
  const baseWageRate =
    shift && shift.computed.paidHours > 0
      ? shift.computed.basePay / shift.computed.paidHours
      : 0;
  const hasSupplementBreakdown =
    !!(shift && shift.computed.supplementPay > 0 && supplementSegments.length > 0);

  const canSave =
    DATE_PATTERN.test(shiftDate) &&
    TIME_PATTERN.test(startTime) &&
    TIME_PATTERN.test(endTime);

  // Check if shift uses snapshots and compare with current settings
  const hasWageSnapshot = Boolean(shift && shift.hourly_wage_snapshot && shift.hourly_wage_snapshot > 0);
  const hasSupplementSnapshot = Boolean(shift && shift.supplement_rules_snapshot?.rules?.length);

  const currentWage = shift ? resolveCurrentWage(userSettings) : null;
  const snapshotWage = shift?.hourly_wage_snapshot;

  // Get current supplement rules for comparison
  const currentSupplementRules = userSettings.use_preset
    ? presetRules
    : (userSettings.custom_supplements?.rules ?? []);
  const snapshotSupplementRules = shift?.supplement_rules_snapshot?.rules ?? [];

  const currentSupplementsCount = currentSupplementRules.length;
  const snapshotSupplementsCount = snapshotSupplementRules.length;

  // Check if values actually differ
  const wagesDiffer = hasWageSnapshot && snapshotWage !== currentWage;
  const supplementsDiffer = hasSupplementSnapshot &&
    !compareSupplementRules(snapshotSupplementRules, currentSupplementRules);

  // Only show the comparison section if values actually differ
  const showSnapshotComparison = wagesDiffer || supplementsDiffer;

  return (
    <Dialog open={isOpen} onOpenChange={(open) => { if (!open) onClose(); }}>
      {!seriesModalOpen && (
        <DialogContent hideCloseButton className="sm:rounded-3xl max-w-[480px]">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-text-primary">
              <IconClock className="h-5 w-5 text-text-muted" aria-hidden />
              {t.pages.shifts.details.title}
            </DialogTitle>
          </DialogHeader>

        {!shift ? (
          <div className="py-6 text-center text-text-secondary">{t.pages.shifts.details.notFound}</div>
        ) : (
          <div className="space-y-4 pt-2">
            <div className="flex items-center justify-between gap-4">
              <div className="text-sm text-text-secondary">{t.pages.shifts.details.date}</div>
              {isEditing ? (
                <Input
                  type="date"
                  value={shiftDate}
                  onChange={(event) => setShiftDate(event.target.value)}
                  disabled={saving}
                  className="w-[160px]"
                />
              ) : (
                <div className="text-base font-medium text-text-primary">
                  {formatDate(shift.shift_date)}
                </div>
              )}
            </div>
            <div className="flex items-center justify-between gap-4">
              <div className="text-sm text-text-secondary">{t.pages.shifts.details.time}</div>
              {isEditing ? (
                <div className="flex items-center gap-2">
                  <TimeInput
                    ref={startInputRef}
                    value={startTime}
                    onChange={setStartTime}
                    onComplete={() => endInputRef.current?.focus()}
                    disabled={saving}
                    className="w-[120px] flex-none"
                  />
                  <span className="text-text-muted">→</span>
                  <TimeInput
                    ref={endInputRef}
                    value={endTime}
                    onChange={setEndTime}
                    disabled={saving}
                    className="w-[120px] flex-none"
                  />
                </div>
              ) : (
                <div className="text-base font-medium text-text-primary">
                  {formatTimeRange(shift.start_time, shift.end_time)}
                </div>
              )}
            </div>

            {saveError ? (
              <div className="text-sm text-error">{saveError}</div>
            ) : null}
            <div className="flex items-center justify-between">
              <div className="text-sm text-text-secondary">{t.pages.shifts.details.paidHours}</div>
              <div className="text-base font-medium text-text-primary">
                {formatHours(shift.computed.paidHours)}
              </div>
            </div>

            <div className="h-px bg-border-subtle" />

            <div className="flex items-center justify-between">
              <div className="text-sm text-text-secondary">{t.pages.shifts.details.basePay}</div>
              <div className="text-base font-medium text-text-primary">
                {formatCurrencyNOKInt(shift.computed.basePay)}
              </div>
            </div>

            {hasSupplementBreakdown ? <div className="h-px bg-border-subtle" /> : null}

            {hasSupplementBreakdown ? (
              <SupplementBreakdown
                baseWage={baseWageRate}
                segments={supplementSegments}
              />
            ) : null}

            {hasSupplementBreakdown ? <div className="h-px bg-border-subtle" /> : null}

            <div className="flex items-center justify-between pt-2">
              <div className="text-sm text-text-secondary">{t.pages.shifts.details.total}</div>
              <div className="text-xl font-semibold text-text-primary">
                {formatCurrencyNOKInt(shift.computed.gross)}
              </div>
            </div>

            {/* Snapshot comparison section */}
            {showSnapshotComparison && (
              <>
                <div className="h-px bg-border-subtle mt-4" />
                <div className="rounded-lg bg-blue-50 dark:bg-blue-900/10 p-4 space-y-3">
                  <div className="space-y-2">
                    <div className="flex items-center gap-2">
                      <IconInfoCircle className="h-5 w-5 text-blue-600 dark:text-blue-400 flex-shrink-0" />
                      <p className="text-sm font-medium text-blue-900 dark:text-blue-100">
                        {t.pages.shifts.details.historicalRates}
                      </p>
                    </div>
                    <p className="text-xs text-blue-700 dark:text-blue-300">
                      {t.pages.shifts.details.usingHistoricalRatesTooltip}
                    </p>
                  </div>

                  {wagesDiffer && (
                    <div className="grid grid-cols-2 gap-3 text-sm">
                      <div className="space-y-1">
                        <p className="text-xs text-blue-600 dark:text-blue-400 font-medium">
                          {t.pages.shifts.details.snapshotWage}
                        </p>
                        <p className="text-sm font-semibold text-blue-900 dark:text-blue-100">
                          {snapshotWage ? formatHourlyRate(snapshotWage) : '—'}
                        </p>
                      </div>
                      <div className="space-y-1">
                        <p className="text-xs text-text-muted font-medium">
                          {t.pages.shifts.details.currentWage}
                        </p>
                        <p className="text-sm text-text-secondary">
                          {currentWage ? formatHourlyRate(currentWage) : '—'}
                        </p>
                      </div>
                    </div>
                  )}

                  {supplementsDiffer && (
                    <div className="grid grid-cols-2 gap-3 text-sm">
                      <div className="space-y-1">
                        <p className="text-xs text-blue-600 dark:text-blue-400 font-medium">
                          {t.pages.shifts.details.snapshotSupplements}
                        </p>
                        <p className="text-sm font-semibold text-blue-900 dark:text-blue-100">
                          {snapshotSupplementsCount} {snapshotSupplementsCount === 1 ? 'regel' : 'regler'}
                        </p>
                      </div>
                      <div className="space-y-1">
                        <p className="text-xs text-text-muted font-medium">
                          {t.pages.shifts.details.currentSupplements}
                        </p>
                        <p className="text-sm text-text-secondary">
                          {currentSupplementsCount} {currentSupplementsCount === 1 ? 'regel' : 'regler'}
                        </p>
                      </div>
                    </div>
                  )}

                  <Button
                    onClick={handleClearSnapshots}
                    disabled={clearingSnapshots}
                    variant="default"
                    className="w-full mt-3"
                  >
                    {clearingSnapshots ? `${t.pages.shifts.details.useCurrentRates}...` : t.pages.shifts.details.useCurrentRates}
                  </Button>
                </div>
              </>
            )}
          </div>
        )}

        <DialogFooter className="mt-4">
          {shift && (
            <div className={cn("grid w-full gap-2", isSeriesGhost && !isEditing && !confirmingDelete ? "grid-cols-2" : "grid-cols-3")}>
              <Button
                onClick={() => {
                  if (confirmingDelete) {
                    handleConfirmDelete();
                  } else {
                    handleDeleteClick();
                  }
                }}
                disabled={saving || isDeleting || isEditing}
                loading={confirmingDelete && isDeleting}
                className={cn(
                  "col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium transition-colors gap-2",
                  isEditing
                    ? "bg-surface-secondary text-text-muted cursor-not-allowed"
                    : "bg-rose-600 text-white hover:bg-rose-700"
                )}
              >
                <IconTrash className="h-4 w-4" />
                {confirmingDelete ? t.pages.shifts.details.confirmDeleteButton : t.pages.shifts.details.deleteButton}
              </Button>
              {isEditing ? (
                <Button
                  onClick={handleSave}
                  disabled={saving || !canSave}
                  className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-semibold text-white bg-blue-600 hover:bg-blue-700 gap-2"
                >
                  <IconCheck className="h-4 w-4" />
                  {t.pages.shifts.details.saveButton}
                </Button>
              ) : (
                <Button
                  onClick={handleEdit}
                  disabled={saving || isDeleting || confirmingDelete}
                  className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium transition-colors gap-2 bg-blue-600 text-white hover:bg-blue-700"
                >
                  <IconPencil className="h-4 w-4" />
                  {t.pages.shifts.details.editButton}
                </Button>
              )}
              {isSeriesGhost && !isEditing && !confirmingDelete && (
                <Button
                  onClick={handleEditSeries}
                  disabled={saving || isDeleting}
                  className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium transition-colors gap-2 bg-purple-600 text-white hover:bg-purple-700"
                >
                  <IconRefresh className="h-4 w-4" />
                  {t.pages.shifts.details.editSeriesButton}
                </Button>
              )}
              {isEditing ? (
                <Button
                  onClick={() => {
                    if (shift) {
                      setStartTime(shift.start_time);
                      setEndTime(shift.end_time);
                      setShiftDate(shift.shift_date);
                    }
                    setSaveError(null);
                    setIsEditing(false);
                  }}
                  disabled={saving || isDeleting}
                  className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900 gap-2"
                >
                  <IconX className="h-4 w-4" />
                  {t.pages.shifts.details.cancelButton}
                </Button>
              ) : confirmingDelete ? (
                <Button
                  onClick={() => {
                    setConfirmingDelete(false);
                  }}
                  disabled={isDeleting}
                  className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900 gap-2"
                >
                  <IconX className="h-4 w-4" />
                  {t.pages.shifts.details.cancelButton}
                </Button>
              ) : (
                <Button
                  onClick={() => {
                    setSaveError(null);
                    onClose();
                  }}
                  disabled={saving || isDeleting}
                  className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900"
                >
                  {t.pages.shifts.details.closeButton}
                </Button>
              )}
            </div>
          )}
        </DialogFooter>
        </DialogContent>
      )}
      {shift?.series_id && (
        <SeriesEditModal
          isOpen={seriesModalOpen}
          seriesId={shift.series_id}
          onClose={(reason) => {
            setSeriesModalOpen(false);
            router.refresh();
            // If the series was deleted, also close the parent ShiftDetails modal
            if (reason === 'deleted') {
              onClose();
            }
          }}
          existingShifts={existingShifts}
          userSettings={userSettings}
          presetRules={presetRules}
        />
      )}
    </Dialog>
  );
}

export default ShiftDetails;
