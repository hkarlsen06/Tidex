'use server';

import { verifySession } from '@/data-access/auth';
import {
  createWageSnapshot,
  updateWageSnapshot,
  deleteWageSnapshot,
  checkExistingSnapshot,
} from '@/data-access/wage-snapshots';
import {
  getTariffVersionForDate,
  getLatestTariffVersion,
  getTariffTypes,
  type TariffVersion,
  type TariffType,
} from '@/data-access/tariff';
import { invalidateAndRevalidate } from '@/lib/revalidation/paths';
import { isISODate } from '@/lib/validation/shift-validators';
import { ERRORS } from '@/lib/errors/messages';
import type { WageSnapshotInput } from '@/data-access/wage-snapshots';

// Default tariff type for HK Retail agreement
const DEFAULT_TARIFF_TYPE = 'hk_retail';

/**
 * Get the tariff version applicable for a specific date.
 * Used when editing an existing snapshot to show historical rates.
 *
 * @param tariffTypeId - The tariff type ID (e.g., 'hk_retail')
 * @param date - ISO date string (YYYY-MM-DD) to get version for
 * @returns The tariff version or null if not found
 */
export async function getTariffVersionForDateAction(
  tariffTypeId: string,
  date: string
): Promise<TariffVersion | null> {
  // Verify authentication (read-only but still requires auth)
  await verifySession();

  // Validate date format to prevent malformed queries
  if (!isISODate(date)) {
    return null;
  }

  return getTariffVersionForDate(tariffTypeId, date);
}

/**
 * Get the latest/current tariff version.
 * Used when creating new snapshots.
 *
 * @param tariffTypeId - The tariff type ID (defaults to 'hk_retail')
 * @returns The latest tariff version or null if not found
 */
export async function getLatestTariffVersionAction(
  tariffTypeId: string = DEFAULT_TARIFF_TYPE
): Promise<TariffVersion | null> {
  // Verify authentication (read-only but still requires auth)
  await verifySession();

  return getLatestTariffVersion(tariffTypeId);
}

/**
 * Get all available tariff types.
 * Used for tariff type selector in settings.
 *
 * @returns Array of available tariff types, ordered by is_default DESC, display_name
 */
export async function getTariffTypesAction(): Promise<TariffType[]> {
  // Verify authentication (read-only but still requires auth)
  await verifySession();

  return getTariffTypes();
}

/**
 * Create a new wage snapshot
 *
 * Flow:
 * 1. Verify authentication
 * 2. Validate from_date format (if not NULL)
 * 3. Check for date conflicts
 * 4. Create snapshot
 * 5. Invalidate cache and revalidate
 *
 * @param data - Wage snapshot data (from_date can be null for baseline)
 * @returns { success: true, id: string } or { error: string }
 */
export async function createWageSnapshotAction(
  data: WageSnapshotInput
): Promise<{ success: true; id: string } | { error: string }> {
  // 1. Verify authentication
  const { user } = await verifySession();

  // 2. Validate from_date format (if not NULL)
  if (data.from_date !== null && !isISODate(data.from_date)) {
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
 * 2. Validate from_date format (if not NULL)
 * 3. Check for date conflicts (excluding current snapshot)
 * 4. Update snapshot
 * 5. Invalidate cache and revalidate
 *
 * @param id - Snapshot ID to update
 * @param data - New wage snapshot data (from_date can be null for baseline)
 * @returns { success: true } or { error: string }
 */
export async function updateWageSnapshotAction(
  id: string,
  data: WageSnapshotInput
): Promise<{ success: true } | { error: string }> {
  // 1. Verify authentication
  const { user } = await verifySession();

  // 2. Validate from_date format (if not NULL)
  if (data.from_date !== null && !isISODate(data.from_date)) {
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
