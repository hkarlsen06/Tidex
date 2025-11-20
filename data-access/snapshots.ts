/**
 * Snapshots Data Access Layer
 *
 * Effect-based internally with Promise wrappers for Next.js compatibility.
 * Uses SettingsService for snapshot preparation based on user settings.
 *
 * Migration status: Using Effect-based services internally
 */

import "server-only";
import { Effect } from "effect";
import { SettingsService } from "@/lib/services/settings";
import { AuthSettingsLive } from "@/lib/layers/app";
import { prepareShiftSnapshots } from "@/lib/payroll/snapshot";
import type { SupplementRule } from "@/lib/payroll/types";
import { logger } from "@/lib/logger";
import { verifySession } from "./auth";

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
 *
 * Promise wrapper around Effect-based services
 */
export async function getCurrentSnapshots(): Promise<ShiftSnapshots> {
  const { user } = await verifySession(); // Ensures user is authenticated

  const program = Effect.gen(function* () {
    const settings = yield* SettingsService;
    const userSettings = yield* settings.getUserSettings(user.id);

    if (!userSettings) {
      return {
        hourly_wage_snapshot: null,
        supplement_rules_snapshot: null,
      };
    }

    // Use pure function for snapshot preparation
    return prepareShiftSnapshots(userSettings);
  }).pipe(Effect.provide(AuthSettingsLive), Effect.scoped);

  try {
    return await Effect.runPromise(program);
  } catch (error: any) {
    logger.error("Failed to prepare shift snapshots:", error);
    // Return null snapshots if settings cannot be loaded
    return {
      hourly_wage_snapshot: null,
      supplement_rules_snapshot: null,
    };
  }
}
