'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import type { RecurringDraft } from '@/lib/recurring/types';
import { detectAllRecurringConflicts } from '@/lib/recurring/conflicts';
import type { ExistingShift } from '@/lib/recurring/conflicts';
import { verifySession } from '@/data-access/auth';
import { invalidateAndRevalidate } from '@/lib/revalidation/paths';


/**
 * Create a new recurring shift pattern
 *
 * Saves the recurring shift definition to the recurring_shifts table.
 * Does NOT materialize individual shifts - that happens separately.
 * Automatically detects and excludes conflicting dates.
 *
 * @param draft - Recurring shift draft with all configuration
 * @param options - Optional configuration
 * @param options.conflictResolution - How to handle conflicts: "exclude_conflicts" (default) or "keep_existing"
 * @returns Created recurring shift ID
 */
export async function createRecurringShift(
  draft: RecurringDraft & { job_id?: string },
  options?: {
    conflictResolution?: 'exclude_conflicts' | 'keep_existing';
  }
): Promise<{ id: string }> {
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

  // Convert HH:mm to timetz format (add timezone offset)
  // For Norwegian users, this is typically +01:00 or +02:00 depending on DST
  // We'll use the system timezone
  const now = new Date();
  const offset = -now.getTimezoneOffset();
  const offsetHours = Math.floor(Math.abs(offset) / 60).toString().padStart(2, '0');
  const offsetMinutes = (Math.abs(offset) % 60).toString().padStart(2, '0');
  const offsetSign = offset >= 0 ? '+' : '-';
  const timezoneOffset = `${offsetSign}${offsetHours}:${offsetMinutes}`;

  const startTimeWithTz = `${draft.start_time}${timezoneOffset}`;
  const endTimeWithTz = `${draft.end_time}${timezoneOffset}`;

  // Determine final exclusions based on conflict resolution strategy
  let allExclusions: string[] = draft.exclusions || [];

  const conflictResolution = options?.conflictResolution || 'exclude_conflicts';

  if (conflictResolution === 'exclude_conflicts') {
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

    // Merge manual exclusions with detected conflicts
    allExclusions = Array.from(
      new Set([...(draft.exclusions || []), ...conflictDates])
    ).sort();
  }
  // If conflictResolution === 'keep_existing', we don't detect/exclude conflicts
  // Recurring shift will create virtual shifts, and existing standalone shifts will remain

  // Insert recurring shift with all exclusions (manual + conflicts)
  const { data, error } = await supabase
    .from('recurring_shifts')
    .insert([
      {
        user_id: user.id,
        ...(draft.job_id ? { job_id: draft.job_id } : {}),
        start_time: startTimeWithTz,
        end_time: endTimeWithTz,
        repeat_interval_weeks: draft.repeat_interval_weeks,
        selected_days: draft.selected_days,
        end_condition: draft.end_condition,
        exclusions: allExclusions,
      },
    ])
    .select('id')
    .single();

  if (error) {
    console.error('Failed to create recurring shift:', error);
    throw new Error(`Failed to create recurring shift: ${error.message}`);
  }

  if (!data) {
    throw new Error('Failed to create recurring shift: no data returned');
  }

  // Invalidate cache and revalidate paths to show new recurring shifts
  invalidateAndRevalidate(user.id);

  return { id: data.id };
}
