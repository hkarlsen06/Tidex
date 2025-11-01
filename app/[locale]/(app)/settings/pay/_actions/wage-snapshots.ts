'use server';

import { verifySession } from '@/data-access/auth';
import {
  createWageSnapshot,
  updateWageSnapshot,
  deleteWageSnapshot,
  checkExistingSnapshot,
} from '@/data-access/wage-snapshots';
import { invalidateAndRevalidate } from '@/lib/revalidation/paths';
import { isISODate } from '@/lib/validation/shift-validators';
import { ERRORS } from '@/lib/errors/messages';
import type { SupplementRule } from '@/data-access/wage-snapshots';

/**
 * Input type for creating/updating wage snapshots
 */
export type WageSnapshotInput = {
  from_date: string; // ISO date (YYYY-MM-DD)
  hourly_wage: number;
  wage_level: number | null; // NULL = custom wage, NUMBER = tariff level
  supplements: { rules: SupplementRule[] };
};

/**
 * Create a new wage snapshot
 *
 * Flow:
 * 1. Verify authentication
 * 2. Validate from_date format
 * 3. Check for date conflicts
 * 4. Create snapshot
 * 5. Invalidate cache and revalidate
 *
 * @param data - Wage snapshot data
 * @returns { success: true, id: string } or { error: string }
 */
export async function createWageSnapshotAction(
  data: WageSnapshotInput
): Promise<{ success: true; id: string } | { error: string }> {
  // 1. Verify authentication
  const { user } = await verifySession();

  // 2. Validate from_date format
  if (!isISODate(data.from_date)) {
    return { error: ERRORS.INVALID_DATE };
  }

  // 3. Check for date conflicts
  const exists = await checkExistingSnapshot(data.from_date);
  if (exists) {
    return { error: ERRORS.WAGE_SNAPSHOT_CONFLICT };
  }

  // 4. Create snapshot
  const result = await createWageSnapshot(data);

  if ('error' in result) {
    return result;
  }

  // 5. Invalidate cache and revalidate
  invalidateAndRevalidate(user.id);

  return result;
}

/**
 * Update an existing wage snapshot
 *
 * Flow:
 * 1. Verify authentication
 * 2. Validate from_date format
 * 3. Check for date conflicts (excluding current snapshot)
 * 4. Update snapshot
 * 5. Invalidate cache and revalidate
 *
 * @param id - Snapshot ID to update
 * @param data - New wage snapshot data
 * @returns { success: true } or { error: string }
 */
export async function updateWageSnapshotAction(
  id: string,
  data: WageSnapshotInput
): Promise<{ success: true } | { error: string }> {
  // 1. Verify authentication
  const { user } = await verifySession();

  // 2. Validate from_date format
  if (!isISODate(data.from_date)) {
    return { error: ERRORS.INVALID_DATE };
  }

  // 3. Check for date conflicts (excluding current snapshot)
  const exists = await checkExistingSnapshot(data.from_date, id);
  if (exists) {
    return { error: ERRORS.WAGE_SNAPSHOT_CONFLICT };
  }

  // 4. Update snapshot
  const result = await updateWageSnapshot(id, data);

  if ('error' in result) {
    return result;
  }

  // 5. Invalidate cache and revalidate
  invalidateAndRevalidate(user.id);

  return result;
}

/**
 * Delete a wage snapshot
 *
 * Flow:
 * 1. Verify authentication
 * 2. Delete snapshot (count is computed in DAL function)
 * 3. Invalidate cache and revalidate
 *
 * @param id - Snapshot ID to delete
 * @returns { success: true, affectedShiftCount: number } or { error: string }
 */
export async function deleteWageSnapshotAction(
  id: string
): Promise<{ success: true; affectedShiftCount: number } | { error: string }> {
  // 1. Verify authentication
  const { user } = await verifySession();

  // 2. Delete snapshot
  const result = await deleteWageSnapshot(id);

  if ('error' in result) {
    return result;
  }

  // 3. Invalidate cache and revalidate
  invalidateAndRevalidate(user.id);

  return result;
}
