import 'server-only';
import { cache } from 'react';
import { cacheTag } from 'next/cache';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';
import type { SupplementRule } from '@/lib/payroll/types';

// =============================================================================
// Types
// =============================================================================

export type TariffType = {
  id: string;
  display_name: string;
  description: string | null;
  country: string;
  is_default: boolean;
};

export type TariffVersion = {
  id: string;
  tariff_type_id: string;
  effective_date: string;
  name: string | null;
  rates: Record<string, number>;
  supplements: { rules: SupplementRule[] };
};

// =============================================================================
// DAL Functions
// =============================================================================

/**
 * Get all available tariff types
 * - Cached globally (tariff types rarely change)
 * - Returns types ordered by is_default DESC, display_name
 */
export const getTariffTypes = cache(async (): Promise<TariffType[]> => {
  'use cache';
  try {
    cacheTag('tariff-types');
    const supabase = await createSupabaseServerClient();

    const { data, error } = await supabase.rpc('get_tariff_types');

    if (error) {
      logger.error('Failed to fetch tariff types:', error);
      return [];
    }

    return (data ?? []) as TariffType[];
  } catch (error) {
    logger.error('Unexpected error fetching tariff types:', error);
    return [];
  }
});

/**
 * Get the default tariff type
 * - Returns the first tariff type with is_default = true
 * - Falls back to 'hk_retail' if no default is set
 */
export async function getDefaultTariffType(): Promise<TariffType | null> {
  const types = await getTariffTypes();
  return types.find((t) => t.is_default) ?? types[0] ?? null;
}

/**
 * Get all versions for a specific tariff type
 * - Cached per tariff type
 * - Returns versions ordered by effective_date DESC (newest first)
 */
export const getTariffVersions = cache(
  async (tariffType: string): Promise<TariffVersion[]> => {
    'use cache';
    try {
      cacheTag('tariff-versions', `tariff-${tariffType}`);
      const supabase = await createSupabaseServerClient();

      const { data, error } = await supabase.rpc('get_tariff_versions', {
        p_tariff_type: tariffType,
      });

      if (error) {
        logger.error(`Failed to fetch tariff versions for ${tariffType}:`, error);
        return [];
      }

      return (data ?? []) as TariffVersion[];
    } catch (error) {
      logger.error(`Unexpected error fetching tariff versions for ${tariffType}:`, error);
      return [];
    }
  }
);

/**
 * Get the applicable tariff version for a specific date
 * - Returns the most recent version where effective_date <= targetDate
 * - Returns null if no applicable version found
 */
export const getTariffVersionForDate = cache(
  async (tariffType: string, targetDate: string): Promise<TariffVersion | null> => {
    'use cache';
    try {
      cacheTag('tariff-versions', `tariff-${tariffType}`);
      const supabase = await createSupabaseServerClient();

      const { data, error } = await supabase.rpc('get_tariff_version_for_date', {
        p_tariff_type: tariffType,
        p_target_date: targetDate,
      });

      if (error) {
        logger.error(`Failed to fetch tariff version for ${tariffType} at ${targetDate}:`, error);
        return null;
      }

      // RPC returns an array, take the first element
      const version = Array.isArray(data) ? data[0] : data;
      return (version as TariffVersion) ?? null;
    } catch (error) {
      logger.error(
        `Unexpected error fetching tariff version for ${tariffType} at ${targetDate}:`,
        error
      );
      return null;
    }
  }
);

/**
 * Get the latest tariff version for a tariff type
 * - Returns the most recent version (highest effective_date)
 * - Useful for onboarding and creating new snapshots
 */
export async function getLatestTariffVersion(
  tariffType: string
): Promise<TariffVersion | null> {
  const versions = await getTariffVersions(tariffType);
  return versions[0] ?? null; // Already sorted by effective_date DESC
}

/**
 * Resolve the hourly wage for a tariff level from a version
 * - Returns the rate for the given wage level
 * - Returns null if the level doesn't exist in the version
 */
export function resolveWageFromVersion(
  version: TariffVersion,
  wageLevel: number
): number | null {
  const key = String(wageLevel);
  return version.rates[key] ?? null;
}
