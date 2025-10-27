'use server';

import { createSupabaseServerClient } from '@/lib/supabase/server';
import type { SeriesDraft } from '@/lib/series/types';
import { detectAllSeriesConflicts } from '@/lib/series/conflicts';
import type { ExistingShift } from '@/lib/series/conflicts';

/**
 * Create a new series shift pattern
 *
 * Saves the series definition to the series_shifts table.
 * Does NOT materialize individual shifts - that happens separately.
 * Automatically detects and excludes conflicting dates.
 *
 * @param draft - Series shift draft with all configuration
 * @returns Created series shift ID
 */
export async function createSeriesShift(draft: SeriesDraft): Promise<{ id: string }> {
  const supabase = await createSupabaseServerClient();

  // Get authenticated user
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (authError || !user) {
    throw new Error('Not authenticated');
  }

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

  // Fetch existing shifts to detect conflicts
  const { data: existingShifts, error: fetchError } = await supabase
    .from('user_shifts')
    .select('shift_date, start_time, end_time')
    .eq('user_id', user.id);

  if (fetchError) {
    console.error('Failed to fetch existing shifts:', fetchError);
    throw new Error(`Failed to fetch existing shifts: ${fetchError.message}`);
  }

  // Detect all conflicts across the entire series
  const conflictDates = await detectAllSeriesConflicts(
    draft,
    (existingShifts || []) as ExistingShift[]
  );

  // Merge manual exclusions with detected conflicts
  const allExclusions = Array.from(
    new Set([...(draft.exclusions || []), ...conflictDates])
  ).sort();

  // Insert series shift with all exclusions (manual + conflicts)
  const { data, error } = await supabase
    .from('series_shifts')
    .insert([
      {
        user_id: user.id,
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
    console.error('Failed to create series shift:', error);
    throw new Error(`Failed to create series shift: ${error.message}`);
  }

  if (!data) {
    throw new Error('Failed to create series shift: no data returned');
  }

  return { id: data.id };
}
