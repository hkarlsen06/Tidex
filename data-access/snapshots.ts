'use server';

import { verifySession } from './auth';
import { getUserSettings } from './settings';
import { prepareShiftSnapshots } from '@/lib/payroll/snapshot';
import type { SupplementRule } from '@/lib/payroll/types';

export type ShiftSnapshots = {
  hourly_wage_snapshot: number | null;
  supplement_rules_snapshot: { rules: SupplementRule[] } | null;
};

/**
 * Get current wage/supplement snapshots for the authenticated user
 * Based on their current settings
 *
 * This function centralizes the logic for preparing shift snapshots,
 * ensuring consistent snapshot preparation across all server actions.
 */
export async function getCurrentSnapshots(): Promise<ShiftSnapshots> {
  const { user } = await verifySession(); // Ensures user is authenticated

  const settings = await getUserSettings(user.id);

  if (!settings) {
    // Return null snapshots if settings cannot be loaded
    return {
      hourly_wage_snapshot: null,
      supplement_rules_snapshot: null,
    };
  }

  return prepareShiftSnapshots(settings);
}
