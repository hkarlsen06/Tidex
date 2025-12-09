'use client';

import { useState, useTransition, useEffect, useRef, useMemo } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogDescription,
} from '@/components/app/Dialog';
import { Button } from '@/components/app/Button';
import { CustomSupplementsEditor } from './CustomSupplementsEditor';
import type { CustomSupplementsEditorData, CustomSupplementsData } from '@/lib/custom-supplements/types';
import type { SupplementRule } from '@/lib/payroll/types';
import { getApplicableSupplements, getAllWeekdaySupplements } from '@/lib/payroll/applicable-supplements';
import { useTranslations } from '@/lib/i18n/client';
import { updateCustomSupplements } from '@/app/[locale]/(app)/shifts/_actions/updateCustomSupplements';

// Compare two editor data objects for equality (ignoring id field)
function editorDataEquals(a: CustomSupplementsEditorData, b: CustomSupplementsEditorData): boolean {
  if (a.rules.length !== b.rules.length) return false;
  return a.rules.every((ruleA, index) => {
    const ruleB = b.rules[index];
    if (!ruleB) return false;
    return (
      ruleA.from === ruleB.from &&
      ruleA.to === ruleB.to &&
      ruleA.rate === ruleB.rate &&
      ruleA.percent === ruleB.percent &&
      ruleA.inputMode === ruleB.inputMode &&
      ruleA.isCustom === ruleB.isCustom
    );
  });
}

interface CustomSupplementsModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  shiftId: string;
  recurringId?: string;
  shiftDate: string;
  startTime: string;
  endTime: string;
  existingSupplements?: CustomSupplementsData | null;
  predefinedRules?: SupplementRule[];
  onSaveSuccess?: (updatedSupplements: CustomSupplementsData | null) => void;
  onSaveError?: (error: string) => void; // Called when save fails after optimistic close
}

// Get weekday (1-7, Mon-Sun) from ISO date
function getWeekday(isoDate: string): number {
  const date = new Date(`${isoDate}T00:00:00Z`);
  const jsDay = date.getUTCDay(); // 0=Sun, 1=Mon, ..., 6=Sat
  // Convert to 1-7 (Mon-Sun): Sun(0)->7, Mon(1)->1, ..., Sat(6)->6
  return jsDay === 0 ? 7 : jsDay;
}

/**
 * Convert HH:MM time string to minutes from midnight
 */
function toMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

/**
 * Check if a rule's time range overlaps with the shift's time window
 */
function ruleOverlapsShift(rule: { from: string; to: string }, startTime: string, endTime: string): boolean {
  const shiftStart = toMinutes(startTime);
  let shiftEnd = toMinutes(endTime);
  if (shiftEnd <= shiftStart) shiftEnd += 24 * 60; // Cross-midnight shift

  const ruleFrom = toMinutes(rule.from);
  let ruleTo = toMinutes(rule.to);
  if (ruleTo <= ruleFrom) ruleTo += 24 * 60; // Cross-midnight rule

  // Check overlap in same-day window
  if (shiftStart < ruleTo && ruleFrom < shiftEnd) return true;

  // For cross-midnight shifts, also check next-day window
  if (shiftEnd > 24 * 60) {
    const nextDayRuleFrom = ruleFrom + 24 * 60;
    const nextDayRuleTo = ruleTo + 24 * 60;
    if (shiftStart < nextDayRuleTo && nextDayRuleFrom < shiftEnd) return true;
  }

  return false;
}

// Convert CustomSupplementsData to CustomSupplementsEditorData
// Only shows rules that overlap with the shift's time window
function toEditorData(
  existingData: CustomSupplementsData | null,
  applicableRules: Omit<SupplementRule, 'days'>[],
  startTime: string,
  endTime: string
): CustomSupplementsEditorData {
  if (existingData && existingData.rules.length > 0) {
    // Filter existing rules to only show those that overlap with the shift time window
    // Non-applicable rules are preserved in the saved data but not shown in the editor
    const applicableExisting = existingData.rules.filter((rule) =>
      ruleOverlapsShift(rule, startTime, endTime)
    );

    return {
      rules: applicableExisting.map((rule, index) => ({
        id: String(index),
        from: rule.from,
        to: rule.to,
        rate: rule.rate,
        percent: rule.percent,
        inputMode: rule.rate !== undefined ? 'rate' : rule.percent !== undefined ? 'percent' : undefined,
        isCustom: rule.isCustom ?? false, // Preserve the saved isCustom flag
      })),
    };
  }

  // No existing supplements - pre-populate with applicable tariff rules
  return {
    rules: applicableRules.map((rule, index) => ({
      id: `tariff-${index}`,
      from: rule.from,
      to: rule.to,
      rate: rule.rate,
      percent: rule.percent,
      inputMode: rule.rate !== undefined ? 'rate' : rule.percent !== undefined ? 'percent' : undefined,
      isCustom: false, // These are from tariff
    })),
  };
}

// Convert CustomSupplementsEditorData to CustomSupplementsData
function fromEditorData(data: CustomSupplementsEditorData): CustomSupplementsData {
  return {
    rules: data.rules
      .filter(rule => rule.from && rule.to && (rule.rate !== undefined || rule.percent !== undefined))
      .map(({ id: _id, inputMode: _inputMode, isCustom, ...rule }) => {
        // Only include rate or percent, not both
        // Cast to HHMM type since we've validated the format
        const base = {
          from: rule.from as `${number}:${number}`,
          to: rule.to as `${number}:${number}`,
          isCustom: isCustom ?? false,
        };
        if (rule.rate !== undefined) {
          return { ...base, rate: rule.rate };
        }
        return { ...base, percent: rule.percent };
      }),
  };
}

export function CustomSupplementsModal({
  open,
  onOpenChange,
  shiftId,
  recurringId,
  shiftDate,
  startTime,
  endTime,
  existingSupplements,
  predefinedRules = [],
  onSaveSuccess,
  onSaveError,
}: CustomSupplementsModalProps) {
  const { t } = useTranslations();
  const prevOpenRef = useRef(open);

  const weekday = useMemo(() => getWeekday(shiftDate), [shiftDate]);

  // Calculate applicable supplements based on shift time window (shown in editor)
  const applicableSupplements = useMemo(() => {
    return getApplicableSupplements(startTime, endTime, weekday, predefinedRules);
  }, [startTime, endTime, weekday, predefinedRules]);

  // Calculate ALL weekday supplements (for saving non-visible ones too)
  const allWeekdaySupplements = useMemo(() => {
    return getAllWeekdaySupplements(weekday, predefinedRules);
  }, [weekday, predefinedRules]);

  // Non-applicable supplements (not shown in editor, but saved for future shift expansion)
  const nonApplicableSupplements = useMemo(() => {
    return allWeekdaySupplements.filter(
      (rule) => !applicableSupplements.some(
        (applicable) =>
          applicable.from === rule.from &&
          applicable.to === rule.to &&
          applicable.rate === rule.rate &&
          applicable.percent === rule.percent
      )
    );
  }, [allWeekdaySupplements, applicableSupplements]);

  const [customSupplements, setCustomSupplements] = useState<CustomSupplementsEditorData>(
    toEditorData(existingSupplements ?? null, applicableSupplements, startTime, endTime)
  );
  const [saving, startTransition] = useTransition();
  const [saveError, setSaveError] = useState<string | null>(null);
  const [showUnsavedPrompt, setShowUnsavedPrompt] = useState(false);
  // Track initial data for change detection (use state instead of ref to trigger re-renders)
  const [initialData, setInitialData] = useState<CustomSupplementsEditorData | null>(null);

  // Sync external open prop with internal state
  useEffect(() => {
    const openedNow = open && !prevOpenRef.current;
    const closedNow = !open && prevOpenRef.current;
    prevOpenRef.current = open;

    if (closedNow) {
      // Reset state on close
      queueMicrotask(() => {
        setSaveError(null);
        setShowUnsavedPrompt(false);
        setInitialData(null);
      });
      return;
    }

    if (openedNow) {
      // Reset editor data when opening and store initial state for change detection
      queueMicrotask(() => {
        const data = toEditorData(existingSupplements ?? null, applicableSupplements, startTime, endTime);
        setCustomSupplements(data);
        setInitialData(data);
        setShowUnsavedPrompt(false);
      });
    }
  }, [open, existingSupplements, applicableSupplements, startTime, endTime]);

  // Check if there are unsaved changes
  const hasUnsavedChanges = useMemo(() => {
    if (!initialData) return false;
    return !editorDataEquals(customSupplements, initialData);
  }, [customSupplements, initialData]);

  // Handle close attempt - check for unsaved changes
  const handleOpenChange = (newOpen: boolean) => {
    if (!newOpen && hasUnsavedChanges) {
      // User trying to close with unsaved changes - show confirmation
      setShowUnsavedPrompt(true);
      return;
    }
    onOpenChange(newOpen);
  };

  // Discard changes and close
  const handleDiscardChanges = () => {
    setShowUnsavedPrompt(false);
    onOpenChange(false);
  };

  const handleSave = () => {
    // If no existing supplements and no changes made, just close (no-op)
    // This prevents unnecessarily saving tariff supplements as custom
    if (!existingSupplements && !hasUnsavedChanges) {
      onOpenChange(false);
      return;
    }

    setSaveError(null);

    const visibleRules = fromEditorData(customSupplements);

    // Check if user has any actual customizations (added custom rules or modified/removed tariff rules)
    const hasCustomizations = visibleRules.rules.some((rule) => rule.isCustom) || hasUnsavedChanges;

    // If no customizations and no existing supplements, don't save anything
    if (!hasCustomizations && !existingSupplements) {
      onOpenChange(false);
      return;
    }

    // Get existing non-applicable custom rules (user-added rules outside shift time window)
    // These need to be preserved since they're not shown in the editor
    const existingNonApplicableCustomRules = existingSupplements?.rules
      .filter((rule) => rule.isCustom && !ruleOverlapsShift(rule, startTime, endTime))
      .map((rule) => ({
        from: rule.from,
        to: rule.to,
        rate: rule.rate,
        percent: rule.percent,
        isCustom: true as const,
      })) ?? [];

    // Merge:
    // 1. Visible rules (user-edited applicable rules)
    // 2. Existing non-applicable custom rules (preserved, not shown in editor)
    // 3. Fresh non-applicable tariff rules (for future shift expansion)
    const allRules = [
      ...visibleRules.rules,
      ...existingNonApplicableCustomRules,
      ...nonApplicableSupplements.map((rule) => ({
        from: rule.from as `${number}:${number}`,
        to: rule.to as `${number}:${number}`,
        rate: rule.rate,
        percent: rule.percent,
        isCustom: false as const, // Non-applicable tariff rules
      })),
    ];

    // Only save if there are valid rules, otherwise clear supplements
    const finalData = allRules.length > 0 ? { rules: allRules } : null;

    // OPTIMISTIC: Close modal and update parent immediately
    onOpenChange(false);
    onSaveSuccess?.(finalData);

    // Run server action in background
    startTransition(async () => {
      try {
        await updateCustomSupplements({
          shiftId,
          recurringId,
          shiftDate,
          customSupplements: finalData,
        });
      } catch (error: any) {
        // Notify parent of error so it can show notification and potentially revert
        onSaveError?.(error?.message || t.pages.shifts.details.errorUpdate);
      }
    });
  };

  const handleCancel = () => {
    if (hasUnsavedChanges) {
      setShowUnsavedPrompt(true);
      return;
    }
    onOpenChange(false);
  };

  const handleReset = () => {
    setSaveError(null);

    // OPTIMISTIC: Close modal and update parent immediately
    onOpenChange(false);
    onSaveSuccess?.(null);

    // Run server action in background
    startTransition(async () => {
      try {
        // Clear custom supplements - the shift will use tariff supplements again
        await updateCustomSupplements({
          shiftId,
          recurringId,
          shiftDate,
          customSupplements: null,
        });
      } catch (error: any) {
        // Notify parent of error so it can show notification
        onSaveError?.(error?.message || t.pages.shifts.details.errorUpdate);
      }
    });
  };

  const isEditing = existingSupplements != null;

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-2xl sm:rounded-3xl max-h-[90vh] overflow-y-auto">
        {/* Unsaved changes confirmation */}
        {showUnsavedPrompt ? (
          <>
            <DialogHeader>
              <DialogTitle>
                {t.components.customSupplementsModal.unsavedChangesTitle}
              </DialogTitle>
              <DialogDescription className="text-sm text-text-secondary">
                {t.components.customSupplementsModal.unsavedChangesDescription}
              </DialogDescription>
            </DialogHeader>
            <DialogFooter className="pt-4">
              <Button variant="ghost" onClick={handleDiscardChanges}>
                {t.components.customSupplementsModal.discard}
              </Button>
              <Button onClick={handleSave} loading={saving} disabled={saving}>
                {t.components.customSupplementsModal.save}
              </Button>
            </DialogFooter>
          </>
        ) : (
          <>
            <DialogHeader>
              <DialogTitle>
                {isEditing
                  ? t.components.customSupplementsModal.titleEdit
                  : t.components.customSupplementsModal.titleAdd}
              </DialogTitle>
              <DialogDescription className="text-sm text-text-secondary">
                {t.components.customSupplementsModal.description}
              </DialogDescription>
            </DialogHeader>

            <div className="py-4">
              <CustomSupplementsEditor
                value={customSupplements}
                onChange={setCustomSupplements}
              />
            </div>

            {/* Reset to standard button - only show when editing */}
            {isEditing && (
              <Button
                variant="outline"
                onClick={handleReset}
                disabled={saving}
                className="w-full text-sm"
              >
                {t.components.customSupplementsModal.resetToStandard}
              </Button>
            )}

            {/* Footnote about snapshot behavior */}
            <p className="text-xs text-text-muted px-1">
              {t.components.customSupplementsModal.footnote}
            </p>

            {saveError && (
              <div className="text-sm text-error">{saveError}</div>
            )}

            <DialogFooter>
              <Button variant="ghost" onClick={handleCancel} disabled={saving}>
                {t.components.customSupplementsModal.cancel}
              </Button>
              <Button
                onClick={handleSave}
                disabled={saving}
                loading={saving}
              >
                {t.components.customSupplementsModal.save}
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}
