'use server';

import { revalidatePath } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';

export interface DeleteShiftsResult {
  success: boolean;
  deletedCount: number;
  error?: string;
}

/**
 * Deletes all shifts for the current user that are NOT in the specified target month.
 * This is used when a free tier user wants to add shifts to a new month.
 *
 * @param targetMonth - The month to keep (YYYY-MM format)
 * @returns Result with number of deleted shifts
 */
export async function deleteShiftsInOtherMonths(targetMonth: string): Promise<DeleteShiftsResult> {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    return { success: false, deletedCount: 0, error: 'Unauthorized' };
  }

  // Validate targetMonth format (YYYY-MM)
  if (!/^\d{4}-\d{2}$/.test(targetMonth)) {
    return { success: false, deletedCount: 0, error: 'Invalid month format' };
  }

  try {
    // First, get all shifts that will be deleted (for counting)
    const { data: shiftsToDelete, error: selectError } = await supabase
      .from('user_shifts')
      .select('id')
      .eq('user_id', user.id)
      .not('shift_date::text', 'like', `${targetMonth}%`);

    if (selectError) {
      console.error('Error selecting shifts to delete:', selectError);
      return { success: false, deletedCount: 0, error: selectError.message };
    }

    if (!shiftsToDelete || shiftsToDelete.length === 0) {
      // No shifts to delete - this is fine
      return { success: true, deletedCount: 0 };
    }

    // Delete all shifts NOT in the target month
    const { error: deleteError } = await supabase
      .from('user_shifts')
      .delete()
      .eq('user_id', user.id)
      .not('shift_date::text', 'like', `${targetMonth}%`);

    if (deleteError) {
      console.error('Error deleting shifts:', deleteError);
      return { success: false, deletedCount: 0, error: deleteError.message };
    }

    // Revalidate the shifts page to reflect changes
    revalidatePath('/shifts');

    return { success: true, deletedCount: shiftsToDelete.length };
  } catch (error) {
    console.error('Unexpected error deleting shifts:', error);
    return {
      success: false,
      deletedCount: 0,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}
