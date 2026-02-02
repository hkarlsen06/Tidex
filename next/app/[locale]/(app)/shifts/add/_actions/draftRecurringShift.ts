'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import type { RecurringDraft } from '@/lib/recurring/types';
import { detectAllRecurringConflicts } from '@/lib/recurring/conflicts';
import type { ExistingShift } from '@/lib/recurring/conflicts';
import { verifySession } from '@/data-access/auth';
import { generateVirtualShiftsForMonth, resolveEndWindow } from '@/lib/recurring/utils';

/**
 * Draft and validate a recurring shift pattern (read-only, no DB writes)
 *
 * Validates the recurring shift definition and detects conflicts with existing shifts.
 * Returns conflict information for user to review before confirming.
 * This is step 1 of the two-step recurring shift creation flow.
 *
 * @param draft - Recurring shift draft with all configuration
 * @returns Conflict data and projected shift count
 */
export async function draftRecurringShift(draft: RecurringDraft): Promise<{
  conflictDates: string[];
  conflictCount: number;
  projectedShiftCount: number;
}> {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Validate draft
  if (!draft.start_time || !/^\d{2}:\d{2}$/.test(draft.start_time)) {
    throw new Error('Invalid start time format (expected HH:mm)');
  }

  if (!draft.end_time || !/^\d{2}:\d{2}$/.test(draft.end_time)) {
    throw new Error('Invalid end time format (expected HH:mm)');
  }

  if (typeof draft.repeat_interval_weeks !== 'number' || draft.repeat_interval_weeks < 0 || draft.repeat_interval_weeks > 8) {
    throw new Error('Invalid repeat interval (expected 0-8)');
  }

  if (!draft.selected_days || Object.keys(draft.selected_days).length === 0) {
    throw new Error('No anchor dates selected');
  }

  // Validate all anchor dates
  const isoDatePattern = /^\d{4}-\d{2}-\d{2}$/;
  for (const [weekday, anchorDate] of Object.entries(draft.selected_days)) {
    if (!isoDatePattern.test(anchorDate)) {
      throw new Error(`Invalid anchor date format for weekday ${weekday}: ${anchorDate}`);
    }
  }

  // Fetch existing shifts to detect conflicts (exclude soft-deleted)
  const { data: existingShifts, error: fetchError } = await supabase
    .from('user_shifts')
    .select('shift_date, start_time, end_time')
    .eq('user_id', user.id)
    .is('deleted_at', null);

  if (fetchError) {
    console.error('Failed to fetch existing shifts:', fetchError);
    throw new Error(`Failed to fetch existing shifts: ${fetchError.message}`);
  }

  // Detect all conflicts across the entire recurring shift
  const conflictDates = await detectAllRecurringConflicts(
    draft,
    (existingShifts || []) as ExistingShift[]
  );

  // Calculate projected shift count
  // Generate virtual shifts for all months in the recurring shift window
  const window = draft.end_condition !== null
    ? resolveEndWindow(draft.selected_days, draft.end_condition)
    : resolveEndWindow(draft.selected_days, null, 6); // 6 months default for infinite

  let totalVirtualShifts = 0;
  if (window) {
    const startYear = window.minMonth.getUTCFullYear();
    const startMonth = window.minMonth.getUTCMonth() + 1;
    const endYear = window.maxMonth.getUTCFullYear();
    const endMonth = window.maxMonth.getUTCMonth() + 1;

    for (let year = startYear; year <= endYear; year++) {
      const monthStart = (year === startYear) ? startMonth : 1;
      const monthEnd = (year === endYear) ? endMonth : 12;

      for (let month = monthStart; month <= monthEnd; month++) {
        const virtualShifts = generateVirtualShiftsForMonth({ year, month }, draft);
        totalVirtualShifts += virtualShifts.length;
      }
    }
  }

  return {
    conflictDates: conflictDates.sort(),
    conflictCount: conflictDates.length,
    projectedShiftCount: totalVirtualShifts,
  };
}
