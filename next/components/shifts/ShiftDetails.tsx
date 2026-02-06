"use client";

import { useEffect, useState, useTransition, useRef, useMemo } from "react";
import { useRouter } from "next/navigation";
import dynamic from "next/dynamic";
import { Pencil, Trash2, Clock, Check, X, RefreshCw, AlertTriangle } from "lucide-react";
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

// Dynamically import CustomSupplementsModal to avoid HMR issues with server action imports
// This modal imports updateCustomSupplements server action which causes Turbopack HMR errors
// when bundled in readOnly contexts (like sharing page) where it's not needed
const CustomSupplementsModal = dynamic(
  () => import("./CustomSupplementsModal").then((mod) => ({ default: mod.CustomSupplementsModal })),
  { ssr: false }
);
import { cn } from "@/lib/cn";
import { TimeInput } from "@/components/app/TimeInput";
import { useTranslations } from "@/lib/i18n/client";
import { formatHours as formatHoursValue } from "@/lib/formatters";
import { useFormatCurrency } from "@/lib/hooks/useFormatCurrency";
import { getDateFormatter } from "@/lib/i18n/locale";
import { RecurringEditModal } from "./RecurringEditModal";
import type { ExistingShift } from "@/lib/recurring/conflicts";
import { queueMutation, isOfflineQueueSupported } from "@/lib/pwa/offline-queue";
import { useOnlineStatus } from "@/lib/hooks/useOnlineStatus";

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

/** Info about a shift that overlaps with the currently viewed shift */
export type OverlappingShiftInfo = {
  id: string;
  start_time: string;
  end_time: string;
};

export type ShiftDetailsProps = {
  isOpen: boolean;
  shift: ShiftWithComputations | null;
  onClose: () => void;
  onDelete?: (shiftId: string | any) => void;
  isDeleting?: boolean;
  existingShifts?: ExistingShift[];
  userSettings?: UserSettings;
  presetRules?: SupplementRule[];
  readOnly?: boolean; // Hide edit/delete buttons when true (e.g., from dashboard)
  showEarnings?: boolean; // When false, hides earnings-related data (for shared shifts with earnings hidden)
  onShiftUpdate?: (updatedSupplements: any) => void; // Called after shift is updated with new custom supplements
  onOptimisticEdit?: (shiftId: string, updates: { shift_date: string; start_time: string; end_time: string }) => void; // Called immediately for optimistic UI update
  onEditSuccess?: () => void; // Called after successful edit server action + router.refresh
  onEditError?: (shiftId: string, error: string) => void; // Called when edit fails to allow parent to revert
  onSupplementSaveError?: (error: string) => void; // Called when custom supplement save fails
  /** Other shifts on the same date that overlap with this shift's time range */
  overlappingShifts?: OverlappingShiftInfo[];
  /** User-specific cache key for browser HTTP cache isolation */
  cacheKey?: string;
  /** Open the modal directly in edit mode */
  initialEditMode?: boolean;
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

// NOTE: Wage comparison functionality removed
// Old per-shift snapshots are deprecated in favor of the wage_snapshots table
// No need to compare with "current" settings since those fields no longer exist

export function ShiftDetails({
  isOpen,
  shift,
  onClose,
  onDelete,
  isDeleting,
  existingShifts = [],
  userSettings = {},
  presetRules = [],
  readOnly = false,
  showEarnings = true,
  onShiftUpdate,
  onOptimisticEdit,
  onEditSuccess,
  onEditError,
  onSupplementSaveError,
  overlappingShifts = [],
  cacheKey,
  initialEditMode = false,
}: ShiftDetailsProps) {
  const { t, locale } = useTranslations();
  const formatCurrency = useFormatCurrency();
  const router = useRouter();
  const [recurringModalOpen, setRecurringModalOpen] = useState(false);
  const [customSupplementsModalOpen, setCustomSupplementsModalOpen] = useState(false);
  const isOffline = useOnlineStatus();

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
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const startInputRef = useRef<HTMLInputElement>(null);
  const endInputRef = useRef<HTMLInputElement>(null);

  // Reset form state when shift changes
  // Note: These setState calls are intentional to reset UI state when the shift prop changes
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setIsEditing(initialEditMode && !readOnly);
    setStartTime(shift?.start_time ?? "");
    setEndTime(shift?.end_time ?? "");
    setShiftDate(shift?.shift_date ?? "");
    setSaveError(null);
    setConfirmingDelete(false);
  }, [shift, initialEditMode, readOnly]);

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

    // If recurring virtual shift, pass recurring info for exclusion handling
    if (shift.recurring_id) {
      onDelete?.({ shiftId: shift.id, recurringId: shift.recurring_id, shiftDate: shift.shift_date });
    } else {
      onDelete?.(shift.id);
    }
  };

  const handleEditRecurring = () => {
    if (!shift?.recurring_id) return;
    setRecurringModalOpen(true);
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

    // Store original values for potential revert
    const originalDate = shift.shift_date;
    const originalStart = shift.start_time;
    const originalEnd = shift.end_time;

    // OPTIMISTIC: Close edit mode and update UI immediately
    setIsEditing(false);
    onOptimisticEdit?.(shift.id, {
      shift_date: shiftDate,
      start_time: startTime,
      end_time: endTime,
    });

    // Run server action in background
    startTransition(async () => {
      try {
        await updateShift({
          id: shift.id,
          shift_date: shiftDate,
          start: startTime,
          end: endTime,
          recurring_id: shift.recurring_id, // Pass recurring_id if present
        });
        router.refresh();
        onEditSuccess?.();
      } catch (error: any) {
        // If offline and queue is supported, queue the mutation
        if (!navigator.onLine && isOfflineQueueSupported()) {
          try {
            await queueMutation({
              type: 'UPDATE',
              endpoint: `/api/shifts/${shift.id}`,
              method: 'PATCH',
              body: JSON.stringify({
                shift_date: shiftDate,
                start: startTime,
                end: endTime,
                recurring_id: shift.recurring_id,
              }),
            });
            // Queued successfully - optimistic update stays
          } catch {
            // Queue failed - revert optimistic update
            onOptimisticEdit?.(shift.id, {
              shift_date: originalDate,
              start_time: originalStart,
              end_time: originalEnd,
            });
            onEditError?.(shift.id, t.pages.shifts.details.errorUpdate);
          }
        } else {
          // Server error - revert optimistic update
          onOptimisticEdit?.(shift.id, {
            shift_date: originalDate,
            start_time: originalStart,
            end_time: originalEnd,
          });
          onEditError?.(shift.id, error?.message || t.pages.shifts.details.errorUpdate);
        }
      }
    });
  };

  const isVirtualShift = Boolean(shift?.recurring_id);

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
      {!recurringModalOpen && (
        <DialogContent
          hideCloseButton
          className="max-w-120"
        >
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-text-primary">
              <Clock className="h-5 w-5 text-text-muted" aria-hidden />
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
                  <div className="flex items-center gap-2">
                    <Input
                      type="date"
                      value={shiftDate}
                      onChange={(event) => setShiftDate(event.target.value)}
                      disabled={saving || !!shift.custom_supplements}
                      title={shift.custom_supplements ? t.pages.shifts.details.dateDisabledCustomSupplements : undefined}
                      className={cn("w-40", shift.custom_supplements && "opacity-60 cursor-not-allowed")}
                    />
                  </div>
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
                      className="w-30 flex-none"
                    />
                    <span className="text-text-muted">→</span>
                    <TimeInput
                      ref={endInputRef}
                      value={endTime}
                      onChange={setEndTime}
                      disabled={saving}
                      className="w-30-none"
                    />
                  </div>
                ) : (
                  <div className="text-base font-medium text-text-primary">
                    {formatTimeRange(shift.start_time, shift.end_time)}
                  </div>
                )}
              </div>

              {/* Overlap warning banner */}
              {overlappingShifts.length > 0 && (
                <div className="rounded-xl border border-orange-400/40 bg-orange-500/10 px-3 py-2 dark:border-orange-500/40 dark:bg-orange-500/15">
                  <div className="flex items-start gap-2">
                    <AlertTriangle className="h-4 w-4 text-orange-500 dark:text-orange-400 mt-0.5 shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-orange-600 dark:text-orange-400">
                        {t.pages.shifts.details.overlapWarningTitle}
                      </p>
                      <p className="text-xs text-orange-600/80 dark:text-orange-400/80 mt-0.5">
                        {overlappingShifts.map((os) => `${os.start_time}–${os.end_time}`).join(", ")}
                      </p>
                    </div>
                  </div>
                </div>
              )}

              {saveError ? (
                <div className="text-sm text-error">{saveError}</div>
              ) : null}
              <div className="flex items-center justify-between">
                <div className="text-sm text-text-secondary">{t.pages.shifts.details.paidHours}</div>
                <div className="text-base font-medium text-text-primary">
                  {formatHours(shift.computed.paidHours)}
                </div>
              </div>

              {/* Earnings sections - hidden when showEarnings is false */}
              {showEarnings && (
                <>
                  <div className="h-px bg-border-subtle" />

                  <div className="flex items-center justify-between">
                    <div className="text-sm text-text-secondary">{t.pages.shifts.details.basePay}</div>
                    <div className="text-base font-medium text-text-primary">
                      {formatCurrency(shift.computed.basePay)}
                    </div>
                  </div>

                  {hasSupplementBreakdown ? <div className="h-px bg-border-subtle" /> : null}

                  {hasSupplementBreakdown ? (
                    <SupplementBreakdown
                      baseWage={baseWageRate}
                      segments={supplementSegments}
                      customSupplements={shift.custom_supplements}
                    />
                  ) : null}

                  {/* Custom Supplements Button */}
                  {isEditing && !confirmingDelete && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setCustomSupplementsModalOpen(true)}
                      disabled={isOffline}
                      className="w-full justify-center gap-2 text-sm text-text-secondary hover:text-text-primary"
                    >
                      <Pencil className="h-4 w-4" />
                      {t.pages.shifts.details.editCustomSupplements}
                    </Button>
                  )}

                  {hasSupplementBreakdown ? <div className="h-px bg-border-subtle" /> : null}

                  <div className="flex items-center justify-between pt-2">
                    <div className="text-sm text-text-secondary">{t.pages.shifts.details.total}</div>
                    <div className="text-xl font-semibold text-text-primary">
                      {formatCurrency(shift.computed.gross)}
                    </div>
                  </div>
                </>
              )}

              {/* Snapshot comparison section */}
              {/* NOTE: Snapshot comparison UI removed - wage data is now in wage_snapshots table */}
            </div>
          )}

          {/* Offline Mode Banner */}
          {isOffline && (
            <div className="mt-4 rounded-xl border border-warning/40 bg-warning-subtle px-3 py-2">
              <p className="text-xs font-medium text-warning">
                📱 <strong>Read-Only Mode</strong> - You&apos;re offline. Cannot edit or delete shifts.
              </p>
            </div>
          )}

          <DialogFooter className="mt-4">
            {shift && (
              <div className={cn("grid w-full gap-2", readOnly ? "grid-cols-1" : isVirtualShift && !isEditing && !confirmingDelete ? "grid-cols-2" : "grid-cols-3")}>
                {!readOnly && (
                  <Button
                    onClick={() => {
                      if (confirmingDelete) {
                        handleConfirmDelete();
                      } else {
                        handleDeleteClick();
                      }
                    }}
                    disabled={saving || isDeleting || isEditing || isOffline}
                    loading={confirmingDelete && isDeleting}
                    title={isOffline ? "Cannot delete shifts while offline" : undefined}
                    className={cn(
                      "col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium transition-colors gap-2",
                      isEditing || isOffline
                        ? "bg-surface-secondary text-text-muted cursor-not-allowed"
                        : "bg-rose-600 text-white hover:bg-rose-700"
                    )}
                  >
                    <Trash2 className="h-4 w-4" />
                    {confirmingDelete ? t.pages.shifts.details.confirmDeleteButton : t.pages.shifts.details.deleteButton}
                  </Button>
                )}
                {!readOnly && isEditing ? (
                  <Button
                    onClick={handleSave}
                    disabled={saving || !canSave}
                    className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-semibold text-white bg-blue-600 hover:bg-blue-700 gap-2"
                  >
                    <Check className="h-4 w-4" />
                    {t.pages.shifts.details.saveButton}
                  </Button>
                ) : !readOnly ? (
                  <Button
                    onClick={handleEdit}
                    disabled={saving || isDeleting || confirmingDelete || isOffline}
                    title={isOffline ? "Cannot edit shifts while offline" : undefined}
                    className={cn(
                      "col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium transition-colors gap-2",
                      isOffline
                        ? "bg-surface-secondary text-text-muted cursor-not-allowed"
                        : "bg-blue-600 text-white hover:bg-blue-700"
                    )}
                  >
                    <Pencil className="h-4 w-4" />
                    {t.pages.shifts.details.editButton}
                  </Button>
                ) : null}
                {!readOnly && isVirtualShift && !isEditing && !confirmingDelete && (
                  <Button
                    onClick={handleEditRecurring}
                    disabled={saving || isDeleting || isOffline}
                    title={isOffline ? "Cannot edit recurring shift while offline" : undefined}
                    className={cn(
                      "col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium transition-colors gap-2",
                      isOffline
                        ? "bg-surface-secondary text-text-muted cursor-not-allowed"
                        : "bg-purple-600 text-white hover:bg-purple-700"
                    )}
                  >
                    <RefreshCw className="h-4 w-4" />
                    {t.pages.shifts.details.editRecurringButton}
                  </Button>
                )}
                {!readOnly && isEditing ? (
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
                    <X className="h-4 w-4" />
                    {t.pages.shifts.details.cancelButton}
                  </Button>
                ) : !readOnly && confirmingDelete ? (
                  <Button
                    onClick={() => {
                      setConfirmingDelete(false);
                    }}
                    disabled={isDeleting}
                    className="col-span-1 h-11 w-full rounded-full px-4 text-sm font-medium border border-border-subtle bg-white text-neutral-900 hover:bg-surface-secondary dark:text-neutral-900 gap-2"
                  >
                    <X className="h-4 w-4" />
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
      {shift?.recurring_id && (
        <RecurringEditModal
          isOpen={recurringModalOpen}
          recurringId={shift.recurring_id}
          onClose={(reason) => {
            setRecurringModalOpen(false);
            router.refresh();
            onEditSuccess?.();
            // If the recurring shift was deleted, also close the parent ShiftDetails modal
            if (reason === 'deleted') {
              onClose();
            }
          }}
          existingShifts={existingShifts}
          userSettings={userSettings}
          presetRules={presetRules}
          cacheKey={cacheKey}
        />
      )}
      {shift && !readOnly && (
        <CustomSupplementsModal
          open={customSupplementsModalOpen}
          onOpenChange={setCustomSupplementsModalOpen}
          shiftId={shift.id}
          recurringId={shift.recurring_id}
          shiftDate={shift.shift_date}
          startTime={shift.start_time}
          endTime={shift.end_time}
          existingSupplements={shift.custom_supplements ?? null}
          predefinedRules={shift.supplement_rules_snapshot?.rules ?? []}
          onSaveSuccess={(updatedSupplements) => {
            // Exit edit mode and notify parent with updated supplements
            setIsEditing(false);
            onShiftUpdate?.(updatedSupplements);
            // Trigger router refresh to get fresh computed data
            router.refresh();
            onEditSuccess?.();
          }}
          onSaveError={onSupplementSaveError}
        />
      )}
    </Dialog>
  );
}

export default ShiftDetails;
