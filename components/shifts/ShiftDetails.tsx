"use client";

import { useEffect, useState, useTransition, useRef } from "react";
import { useRouter } from "next/navigation";
import { IconPencil, IconTrash, IconClock, IconCheck, IconX } from "@tabler/icons-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@components/app/Dialog";
import { Button } from "@components/app/Button";
import { Input } from "@components/app/Input";
import type { ShiftWithComputations } from "@/lib/payroll";
import SupplementBreakdown, { type SupplementSegmentInput } from "./SupplementBreakdown";
import { updateShift } from "@/app/[locale]/(app)/shifts/_actions/updateShift";
import { cn } from "@/lib/cn";
import { TimeInput } from "@/components/app/TimeInput";
import { useTranslations } from "@/lib/i18n/client";

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
  onDelete?: (shiftId: string) => void;
  isDeleting?: boolean;
};

const numberFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

const hoursFormatter = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const dayFormatter = new Intl.DateTimeFormat("nb-NO", { weekday: "long" });
const dateFormatter = new Intl.DateTimeFormat("nb-NO", {
  day: "2-digit",
  month: "long",
});

function capitalize(input: string) {
  return input.charAt(0).toUpperCase() + input.slice(1);
}

function formatDate(dateISO: string) {
  const d = new Date(`${dateISO}T00:00:00Z`);
  const day = capitalize(dayFormatter.format(d));
  const label = capitalize(dateFormatter.format(d));
  return `${label} · ${day}`;
}

function formatTimeRange(start: string, end: string) {
  return `${start} – ${end}`;
}

function formatHours(value: number) {
  return `${hoursFormatter.format(value)}t`;
}

function formatCurrencyNOKInt(value: number) {
  return `${numberFormatter.format(Math.round(value))} kr`;
}

export function ShiftDetails({
  isOpen,
  shift,
  onClose,
  onDelete,
  isDeleting,
}: ShiftDetailsProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const [isEditing, setIsEditing] = useState(false);
  const [startTime, setStartTime] = useState("");
  const [endTime, setEndTime] = useState("");
  const [shiftDate, setShiftDate] = useState("");
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saving, startTransition] = useTransition();
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
    onDelete?.(shift.id);
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
        });
        setIsEditing(false);
        router.refresh();
      } catch (error: any) {
        setSaveError(error?.message || t.pages.shifts.details.errorUpdate);
      }
    });
  };

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

  return (
    <Dialog open={isOpen} onOpenChange={(open) => { if (!open) onClose(); }}>
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
          </div>
        )}

        <DialogFooter className="mt-4">
          {shift && (
            <div className="grid w-full grid-cols-3 gap-2">
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
    </Dialog>
  );
}

export default ShiftDetails;
