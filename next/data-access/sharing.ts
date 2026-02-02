/**
 * Sharing Data Access Layer
 *
 * Effect-based internally with Promise wrappers for Next.js compatibility.
 * Uses SharingService for shift sharing data access.
 *
 * Migration status: Using Effect-based SharingService internally
 */

import "server-only";
import { cache } from "react";
import { cacheTag } from "next/cache";
import { cookies } from "next/headers";
import { Effect } from "effect";
import {
  SharingService,
  type SharedUser,
  type ShareRecipient,
  type NotificationFrequency,
} from "@/lib/services/sharing";

// Re-export NotificationFrequency type
export type { NotificationFrequency };
import { SharingLive, ShiftsLive } from "@/lib/layers/app";
import { ShiftsService } from "@/lib/services/shifts";
import { logger } from "@/lib/logger";
import { verifySession } from "@/data-access/auth";
import type { ShiftWithComputations, UserSettings, WageSnapshot, ShiftRow } from "@/lib/payroll";
import type { PayoutTaxSettings } from "@/lib/services/shifts";
import { createSupabaseServerClient } from "@/lib/supabase/server";

// Re-export types for backward compatibility
export type { SharedUser, ShareRecipient };

/**
 * Unified friend entry that combines both directions of sharing
 * - sharesWithMe: They share their shifts with me (I can see their shifts)
 * - iShareWith: I share my shifts with them (they can see my shifts)
 */
export type Friend = {
  readonly id: string;
  readonly email: string | null;
  readonly phone: string | null;
  readonly firstName: string | null;
  readonly profilePictureUrl: string | null;
  readonly oauthAvatarUrl: string | null;
  /**
   * If they share with me:
   * - blocked: whether I've hidden them from my view
   * - showEarningsToMe: whether they allow me to see their earnings
   * - sharedWithMeAt: when they started sharing with me
   * - notificationFrequency: how often I want notifications from this sharer
   */
  readonly sharesWithMe: {
    readonly blocked: boolean;
    readonly showEarningsToMe: boolean;
    readonly sharedAt: string;
    readonly notificationFrequency: NotificationFrequency;
  } | null;
  /**
   * If I share with them:
   * - showEarningsToThem: whether I allow them to see my earnings
   * - sharedWithThemAt: when I started sharing with them
   */
  readonly iShareWith: {
    readonly showEarningsToThem: boolean;
    readonly sharedAt: string;
  } | null;
};

/**
 * Internal implementation of getUsersWhoSharedWithMe
 * @internal - Do not call directly, use getUsersWhoSharedWithMe()
 */
async function getUsersWhoSharedWithMeInternal(
  userId: string
): Promise<SharedUser[]> {
  "use cache: private";
  cacheTag(`user-${userId}`, "sharing-received");

  await cookies();

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    const data = yield* sharing.getUsersWhoSharedWithMe(userId);
    return data;
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);
    return [...result];
  } catch (error: any) {
    logger.error("Failed to fetch users who shared with me:", error);
    return [];
  }
}

/**
 * Get users who have shared their shifts with the current user
 * - Uses React cache() for request deduplication
 * - Cache is scoped by userId
 *
 * Promise wrapper around Effect-based SharingService
 */
export const getUsersWhoSharedWithMe = cache(
  async (userId: string): Promise<SharedUser[]> => {
    const { user } = await verifySession();

    if (user.id !== userId) {
      throw new Error("User ID mismatch - potential security violation");
    }

    return getUsersWhoSharedWithMeInternal(userId);
  }
);

/**
 * Get users who have shared their shifts with the current user
 * - Direct implementation for API routes (bypasses Effect layer)
 * - For use in API routes where auth is handled via Bearer token
 * - Does NOT require cookie-based session
 *
 * @param userId - The authenticated user's ID (already verified by caller)
 */
export async function getUsersWhoSharedWithMeWithUserId(
  userId: string
): Promise<SharedUser[]> {
  const { createClient } = await import("@supabase/supabase-js");

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    logger.error("Missing Supabase URL or service role key");
    return [];
  }

  const adminClient = createClient(url, serviceRoleKey, {
    auth: { persistSession: false },
  });

  try {
    // Query shift_shares where viewer_id = userId and not blocked
    const { data: shares, error: sharesError } = await adminClient
      .from("shift_shares")
      .select("owner_id, created_at, show_earnings, muted")
      .eq("viewer_id", userId)
      .eq("blocked", false)
      .order("created_at", { ascending: false });

    if (sharesError) {
      logger.error("Failed to fetch shares:", sharesError);
      return [];
    }

    if (!shares || shares.length === 0) {
      return [];
    }

    // Get profile pictures from user_settings
    const ownerIds = shares.map((s) => s.owner_id);
    const { data: settings } = await adminClient
      .from("user_settings")
      .select("user_id, profile_picture_url")
      .in("user_id", ownerIds);

    const settingsMap = new Map(
      (settings ?? []).map((s: { user_id: string; profile_picture_url: string | null }) => [s.user_id, s.profile_picture_url])
    );

    // Get email/phone/name/avatar from admin client
    type AuthUserInfo = { email: string | null; phone: string | null; firstName: string | null; oauthAvatarUrl: string | null };
    const usersMap = new Map<string, AuthUserInfo>();

    const { data: adminData, error: adminError } = await adminClient.auth.admin.listUsers({
      page: 1,
      perPage: 1000,
    });

    if (!adminError && adminData?.users) {
      for (const user of adminData.users) {
        if (ownerIds.includes(user.id)) {
          const metadata = user.user_metadata ?? {};
          usersMap.set(user.id, {
            email: user.email ?? null,
            phone: user.phone ?? null,
            firstName: (metadata.full_name as string) ?? (metadata.name as string) ?? null,
            oauthAvatarUrl: (metadata.avatar_url as string) ?? (metadata.picture as string) ?? null,
          });
        }
      }
    }

    // Build SharedUser objects
    const result: SharedUser[] = shares.map((share) => {
      const userInfo = usersMap.get(share.owner_id);
      const profilePictureUrl = settingsMap.get(share.owner_id) ?? null;
      const muted = share.muted ?? false;

      return {
        id: share.owner_id,
        email: userInfo?.email ?? null,
        phone: userInfo?.phone ?? null,
        firstName: userInfo?.firstName ?? null,
        profilePictureUrl,
        oauthAvatarUrl: userInfo?.oauthAvatarUrl ?? null,
        sharedAt: share.created_at,
        showEarnings: share.show_earnings ?? false,
        notificationFrequency: muted ? "muted" as const : "instant" as const,
      };
    });

    return result;
  } catch (error) {
    logger.error("Failed to fetch users who shared with me:", error);
    return [];
  }
}

/**
 * Internal implementation of getMyShareRecipients
 * @internal - Do not call directly, use getMyShareRecipients()
 */
async function getMyShareRecipientsInternal(
  userId: string
): Promise<ShareRecipient[]> {
  "use cache: private";
  cacheTag(`user-${userId}`, "sharing-given");

  await cookies();

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    const data = yield* sharing.getMyShareRecipients(userId);
    return data;
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);
    return [...result];
  } catch (error: any) {
    logger.error("Failed to fetch my share recipients:", error);
    return [];
  }
}

/**
 * Get users the current user has shared their shifts with
 * - Uses React cache() for request deduplication
 * - Cache is scoped by userId
 *
 * Promise wrapper around Effect-based SharingService
 */
export const getMyShareRecipients = cache(
  async (userId: string): Promise<ShareRecipient[]> => {
    const { user } = await verifySession();

    if (user.id !== userId) {
      throw new Error("User ID mismatch - potential security violation");
    }

    return getMyShareRecipientsInternal(userId);
  }
);

/**
 * Strip earnings data from a shift, keeping only hours-related fields
 * Used when showEarnings is false for a share relationship
 *
 * Structure: ShiftWithComputations = ShiftRow & { computed: ShiftComputed }
 * - computed contains: gross, basePay, supplementPay, wagePeriods
 * We zero out monetary values while preserving hour data
 */
function stripEarningsFromShift(shift: ShiftWithComputations): ShiftWithComputations {
  return {
    ...shift,
    // Zero out the computed earnings fields
    computed: {
      ...shift.computed,
      basePay: 0,
      supplementPay: 0,
      gross: 0,
      // Clear wage periods to hide supplement breakdown
      wagePeriods: [],
      originalWagePeriods: [],
    },
    // Clear tax info
    tax_enabled: undefined,
    tax_percentage: undefined,
  };
}

/**
 * Aggregates for shared shifts (earnings may be hidden)
 */
export type SharedShiftsAggregates = {
  totalHours: number;
  totalEarnings: number | null; // null when showEarnings is false
};

/**
 * Internal implementation of getSharedUserShifts
 * @internal - Do not call directly, use getSharedUserShifts()
 */
async function getSharedUserShiftsInternal(
  viewerId: string,
  ownerId: string,
  options: { startDate?: string; endDate?: string; limit?: number; year?: number; month?: number } = {}
): Promise<{
  shifts: ShiftWithComputations[];
  defaultView: string;
  settings: UserSettings;
  aggregates: SharedShiftsAggregates;
  showEarnings: boolean;
  payoutTaxSettings: PayoutTaxSettings;
  wageSnapshots: WageSnapshot[];
}> {
  "use cache: private";
  cacheTag(`user-${ownerId}`, "shared-shifts");

  await cookies();

  // First verify the viewer has access and get share settings
  const shareSettingsProgram = Effect.gen(function* () {
    const sharing = yield* SharingService;
    return yield* sharing.getShareSettings(viewerId, ownerId);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  const shareSettings = await Effect.runPromise(shareSettingsProgram);

  if (!shareSettings) {
    logger.warn(`User ${viewerId} attempted to access shifts of ${ownerId} without permission`);
    return {
      shifts: [],
      defaultView: "calendar",
      settings: {},
      aggregates: { totalHours: 0, totalEarnings: null },
      showEarnings: false,
      payoutTaxSettings: null,
      wageSnapshots: [],
    };
  }

  const showEarnings = shareSettings.showEarnings;

  // Now fetch the shifts using the owner's ID (since RLS allows it through shift_shares)
  // We skip auth check because we've already verified share access above
  const program = Effect.gen(function* () {
    const shifts = yield* ShiftsService;
    const data = yield* shifts.getShiftsWithComputations({
      userId: ownerId,
      startDate: options.startDate,
      endDate: options.endDate,
      limit: options.limit,
      year: options.year,
      month: options.month,
      skipAuthCheck: true, // Access already verified via getShareSettings
    });
    return data;
  }).pipe(Effect.provide(ShiftsLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);

    // Fetch owner's wage snapshots for client-side tax calculation
    // This allows computing payoutTaxSettings for any month without additional API calls
    let wageSnapshots: WageSnapshot[] = [];
    if (showEarnings) {
      const supabase = await createSupabaseServerClient();
      const { data: snapshots } = await supabase
        .from("wage_snapshots")
        .select("*")
        .eq("user_id", ownerId)
        .is("deleted_at", null) // Exclude soft-deleted snapshots
        .order("from_date", { ascending: false, nullsFirst: false });
      wageSnapshots = (snapshots ?? []) as WageSnapshot[];
    }

    // SECURITY: If showEarnings is false, strip all earnings data server-side
    // This is the security enforcement point - data is filtered before reaching the client
    if (!showEarnings) {
      return {
        shifts: result.shifts.map(stripEarningsFromShift),
        defaultView: result.defaultView,
        settings: {
          ...result.settings,
          // Optionally hide wage-related settings too
        },
        aggregates: {
          totalHours: result.aggregates.totalHours,
          totalEarnings: null, // Hide total earnings
        },
        showEarnings: false,
        payoutTaxSettings: null, // Hide tax settings when earnings hidden
        wageSnapshots: [], // Hide snapshots when earnings hidden
      };
    }

    return {
      shifts: [...result.shifts],
      defaultView: result.defaultView,
      settings: result.settings,
      aggregates: result.aggregates,
      showEarnings: true,
      payoutTaxSettings: result.payoutTaxSettings,
      wageSnapshots,
    };
  } catch (error: any) {
    logger.error("Failed to fetch shared user shifts:", error);
    return {
      shifts: [],
      defaultView: "calendar",
      settings: {},
      aggregates: { totalHours: 0, totalEarnings: null },
      showEarnings: false,
      payoutTaxSettings: null,
      wageSnapshots: [],
    };
  }
}

/**
 * Get computed shifts for a user who has shared their shifts with the viewer
 * - Verifies viewer has share access before returning data
 * - Filters out earnings data if showEarnings is false (security enforcement)
 * - Uses React cache() for request deduplication
 *
 * Promise wrapper around Effect-based services
 */
export const getSharedUserShifts = cache(
  async (
    ownerId: string,
    options: { startDate?: string; endDate?: string; limit?: number; year?: number; month?: number } = {}
  ): Promise<{
    shifts: ShiftWithComputations[];
    defaultView: string;
    settings: UserSettings;
    aggregates: SharedShiftsAggregates;
    showEarnings: boolean;
    payoutTaxSettings: PayoutTaxSettings;
    wageSnapshots: WageSnapshot[];
  }> => {
    const { user } = await verifySession();

    return getSharedUserShiftsInternal(user.id, ownerId, options);
  }
);

/**
 * Get computed shifts for a user who has shared their shifts with the viewer
 * - Direct implementation for API routes (bypasses Effect layer)
 * - For use in API routes where auth is handled via Bearer token
 * - Does NOT require cookie-based session
 *
 * @param viewerId - The authenticated viewer's user ID (already verified by caller)
 * @param ownerId - The shift owner's user ID
 * @param options - Query options (startDate, endDate, limit, year, month)
 */
export async function getSharedUserShiftsWithViewerId(
  viewerId: string,
  ownerId: string,
  options: { startDate?: string; endDate?: string; limit?: number; year?: number; month?: number } = {}
): Promise<{
  shifts: ShiftWithComputations[];
  defaultView: string;
  settings: UserSettings;
  aggregates: SharedShiftsAggregates;
  showEarnings: boolean;
  payoutTaxSettings: PayoutTaxSettings;
  wageSnapshots: WageSnapshot[];
}> {
  const { createClient } = await import("@supabase/supabase-js");
  const { computeShift, PRESET_SUPPLEMENT_RULES } = await import("@/lib/payroll");
  const { generateVirtualShiftsForMonth } = await import("@/lib/recurring/utils");
  const { cleanTime } = await import("@/lib/time-utils");

  // Calculate the payout date for a given earnings month.
  // Payout is in the month after earnings, on the user's payroll_day.
  const calculatePayoutDate = (
    earningsYear: number,
    earningsMonth: number,
    payrollDay: number
  ): string => {
    let payoutYear = earningsYear;
    let payoutMonth = earningsMonth + 1;

    if (payoutMonth > 12) {
      payoutMonth = 1;
      payoutYear += 1;
    }

    const daysInPayoutMonth = new Date(payoutYear, payoutMonth, 0).getDate();
    const adjustedPayrollDay = Math.min(payrollDay, daysInPayoutMonth);

    return `${payoutYear}-${String(payoutMonth).padStart(2, "0")}-${String(adjustedPayrollDay).padStart(2, "0")}`;
  };

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    logger.error("Missing Supabase URL or service role key");
    return {
      shifts: [],
      defaultView: "calendar",
      settings: {},
      aggregates: { totalHours: 0, totalEarnings: null },
      showEarnings: false,
      payoutTaxSettings: null,
      wageSnapshots: [],
    };
  }

  const adminClient = createClient(url, serviceRoleKey, {
    auth: { persistSession: false },
  });

  try {
    // Step 1: Verify share access
    const { data: shareSettings, error: shareError } = await adminClient
      .from("shift_shares")
      .select("show_earnings, blocked")
      .eq("owner_id", ownerId)
      .eq("viewer_id", viewerId)
      .maybeSingle();

    if (shareError || !shareSettings || shareSettings.blocked) {
      logger.warn(`User ${viewerId} attempted to access shifts of ${ownerId} without permission`);
      return {
        shifts: [],
        defaultView: "calendar",
        settings: {},
        aggregates: { totalHours: 0, totalEarnings: null },
        showEarnings: false,
        payoutTaxSettings: null,
        wageSnapshots: [],
      };
    }

    const showEarnings = shareSettings.show_earnings ?? false;

    // Step 2: Calculate date range
    const { startDate, endDate, limit = 100, year, month } = options;

    // Step 3: Fetch user settings, shifts, recurring shifts, and snapshots in parallel
    const [settingsResult, shiftsResult, recurringResult, snapshotsResult] = await Promise.all([
      adminClient
        .from("user_settings")
        .select("*")
        .eq("user_id", ownerId)
        .maybeSingle(),
      adminClient
        .from("user_shifts")
        .select("*")
        .eq("user_id", ownerId)
        .is("deleted_at", null)
        .gte("shift_date", startDate ?? "1900-01-01")
        .lte("shift_date", endDate ?? "2100-12-31")
        .order("shift_date", { ascending: false })
        .limit(limit),
      adminClient
        .from("recurring_shifts")
        .select("*")
        .eq("user_id", ownerId)
        .is("deleted_at", null),
      adminClient
        .from("wage_snapshots")
        .select("*")
        .eq("user_id", ownerId)
        .is("deleted_at", null)
        .order("from_date", { ascending: false, nullsFirst: false }),
    ]);

    const userSettings = settingsResult.data ?? {};
    const shifts = (shiftsResult.data ?? []) as ShiftRow[];
    const recurringShifts = recurringResult.data ?? [];
    const snapshots = (snapshotsResult.data ?? []) as WageSnapshot[];

    // Step 4: Build snapshot map for date lookup
    const baselineSnapshot = snapshots.find((s) => s.from_date === null) ?? null;
    const getSnapshotForDate = (date: string): WageSnapshot | null => {
      const applicableSnapshot = snapshots.find(
        (s) => s.from_date !== null && s.from_date <= date
      );
      return applicableSnapshot || baselineSnapshot || null;
    };

    // Step 5: Generate virtual shifts from recurring patterns
    type VirtualShift = { date: string; weekday: number };
    const virtualShiftsByRecurring = new Map<string, VirtualShift[]>();

    if (startDate && endDate) {
      const startYear = new Date(startDate).getFullYear();
      const startMonth = new Date(startDate).getMonth() + 1;
      const endYear = new Date(endDate).getFullYear();
      const endMonth = new Date(endDate).getMonth() + 1;

      for (const recurring of recurringShifts) {
        const recurringVirtuals: VirtualShift[] = [];
        let currentYear = startYear;
        let currentMonth = startMonth;

        while (
          currentYear < endYear ||
          (currentYear === endYear && currentMonth <= endMonth)
        ) {
          const virtualShifts = generateVirtualShiftsForMonth(
            { year: currentYear, month: currentMonth },
            {
              start_time: cleanTime(recurring.start_time),
              end_time: cleanTime(recurring.end_time),
              repeat_interval_weeks: recurring.repeat_interval_weeks,
              selected_days: recurring.selected_days,
              end_condition: recurring.end_condition,
              exclusions: recurring.exclusions || [],
            }
          );

          for (const vs of virtualShifts) {
            if (vs.date >= startDate && vs.date <= endDate) {
              recurringVirtuals.push(vs);
            }
          }

          currentMonth++;
          if (currentMonth > 12) {
            currentMonth = 1;
            currentYear++;
          }
        }

        virtualShiftsByRecurring.set(recurring.id, recurringVirtuals);
      }
    }

    // Step 6: Compute payroll for all shifts
    const payrollDay = userSettings.payroll_day ?? 1;
    const getPayoutDateForShift = (shiftDate: string): string => {
      const [y, m] = shiftDate.split("-").map(Number);
      return calculatePayoutDate(y, m, payrollDay);
    };

    const computedShifts: ShiftWithComputations[] = shifts.map((shift) => {
      const snapshot = getSnapshotForDate(shift.shift_date);
      const payoutDate = getPayoutDateForShift(shift.shift_date);
      const taxSnapshot = getSnapshotForDate(payoutDate);
      const supplementRulesSnapshot =
        shift.supplement_rules_snapshot ??
        (snapshot?.supplements ? snapshot.supplements : null);

      return {
        ...shift,
        supplement_rules_snapshot: supplementRulesSnapshot,
        computed: computeShift(shift, userSettings, PRESET_SUPPLEMENT_RULES, snapshot),
        tax_enabled: taxSnapshot?.tax_enabled ?? false,
        tax_percentage: taxSnapshot?.tax_percentage ?? 0,
      };
    });

    // Step 7: Compute recurring virtual shifts
    const recurringVirtualShifts: ShiftWithComputations[] = [];
    for (const recurring of recurringShifts) {
      const cachedVirtuals = virtualShiftsByRecurring.get(recurring.id) ?? [];

      for (const virtualShift of cachedVirtuals) {
        const snapshot = getSnapshotForDate(virtualShift.date);
        const payoutDate = getPayoutDateForShift(virtualShift.date);
        const taxSnapshot = getSnapshotForDate(payoutDate);
        const customSupplements = recurring.date_specific_supplements?.[virtualShift.date] ?? null;

        const shiftRow: ShiftRow = {
          id: `virtual-${recurring.id}-${virtualShift.date}`,
          user_id: ownerId,
          shift_date: virtualShift.date,
          start_time: cleanTime(recurring.start_time),
          end_time: cleanTime(recurring.end_time),
          custom_supplements: customSupplements,
          recurring_id: recurring.id,
          recurring_anchor_weekday: virtualShift.weekday,
        };

        recurringVirtualShifts.push({
          ...shiftRow,
          supplement_rules_snapshot: snapshot?.supplements ?? null,
          computed: computeShift(shiftRow, userSettings, PRESET_SUPPLEMENT_RULES, snapshot),
          tax_enabled: taxSnapshot?.tax_enabled ?? false,
          tax_percentage: taxSnapshot?.tax_percentage ?? 0,
        });
      }
    }

    // Step 8: Merge and sort shifts
    const allShifts = [...computedShifts, ...recurringVirtualShifts].sort(
      (a, b) => a.shift_date.localeCompare(b.shift_date)
    );

    // Step 9: Calculate aggregates
    const aggregates: SharedShiftsAggregates = allShifts.reduce(
      (acc, shift) => ({
        totalHours: acc.totalHours + shift.computed.paidHours,
        totalEarnings: (acc.totalEarnings ?? 0) + shift.computed.gross,
      }),
      { totalHours: 0, totalEarnings: 0 as number | null }
    );

    // Step 10: Get payout tax settings for the requested month
    let payoutTaxSettings: PayoutTaxSettings = null;
    if (year && month) {
      const payoutDate = calculatePayoutDate(year, month, payrollDay);
      const payoutSnapshot = getSnapshotForDate(payoutDate);
      if (payoutSnapshot) {
        payoutTaxSettings = {
          enabled: payoutSnapshot.tax_enabled ?? false,
          percentage: payoutSnapshot.tax_percentage ?? 0,
        };
      }
    }

    // Step 11: Strip earnings if not allowed
    if (!showEarnings) {
      return {
        shifts: allShifts.map(stripEarningsFromShift),
        defaultView: userSettings.default_shifts_view ?? "calendar",
        settings: userSettings,
        aggregates: { totalHours: aggregates.totalHours, totalEarnings: null },
        showEarnings: false,
        payoutTaxSettings: null,
        wageSnapshots: [],
      };
    }

    return {
      shifts: allShifts,
      defaultView: userSettings.default_shifts_view ?? "calendar",
      settings: userSettings,
      aggregates,
      showEarnings: true,
      payoutTaxSettings,
      wageSnapshots: snapshots,
    };
  } catch (error) {
    logger.error("Failed to fetch shared user shifts:", error);
    return {
      shifts: [],
      defaultView: "calendar",
      settings: {},
      aggregates: { totalHours: 0, totalEarnings: null },
      showEarnings: false,
      payoutTaxSettings: null,
      wageSnapshots: [],
    };
  }
}

/**
 * Update share settings for a specific recipient
 * - Only the owner can update settings for their shares
 * - Used to toggle earnings visibility
 *
 * Promise wrapper around Effect-based SharingService
 */
export async function updateShareSettings(
  recipientId: string,
  settings: { showEarnings: boolean }
): Promise<{ success: boolean; error?: string }> {
  const { user } = await verifySession();

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.updateShareSettings(user.id, recipientId, settings);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);
    return { success: true };
  } catch (error: any) {
    logger.error("Failed to update share settings:", error);
    return { success: false, error: "Failed to update share settings" };
  }
}

/**
 * Shift preview data for a sharer - shows their next/current/previous shift
 */
export type SharerShiftPreview = {
  readonly sharerId: string;
  readonly shift: ShiftWithComputations | null;
  readonly status: "active" | "upcoming" | "past" | null;
  readonly showEarnings: boolean;
};

/**
 * Get shift previews for all sharers (internal implementation)
 * For each sharer, finds their next/current/previous shift relative to now
 * Used by both the DAL (web) and API route (iOS)
 */
export async function getSharerShiftPreviewsWithViewerId(
  viewerId: string,
  sharerIds: string[]
): Promise<SharerShiftPreview[]> {
  if (sharerIds.length === 0) {
    return [];
  }

  const now = new Date();

  // Fetch shifts for all sharers in parallel
  // We fetch a window: 30 days back to 30 days ahead
  // This ensures we show "worked 2 weeks ago" for inactive users
  const monthAgo = new Date(now);
  monthAgo.setDate(monthAgo.getDate() - 30);
  const monthFromNow = new Date(now);
  monthFromNow.setDate(monthFromNow.getDate() + 30);

  const startDate = monthAgo.toISOString().slice(0, 10);
  const endDate = monthFromNow.toISOString().slice(0, 10);

  const previews = await Promise.all(
    sharerIds.map(async (sharerId): Promise<SharerShiftPreview> => {
      try {
        // Fetch shifts within our ±30 day window
        // We need enough to find the most relevant one (active > upcoming > recent past)
        const { shifts, showEarnings } = await getSharedUserShiftsInternal(
          viewerId,
          sharerId,
          { startDate, endDate, limit: 100 }
        );

        if (!shifts || shifts.length === 0) {
          return { sharerId, shift: null, status: null, showEarnings };
        }

        // Sort shifts by date and time
        const sortedShifts = [...shifts].sort((a, b) => {
          const dateCompare = a.shift_date.localeCompare(b.shift_date);
          if (dateCompare !== 0) return dateCompare;
          return a.start_time.localeCompare(b.start_time);
        });

        // Find active, upcoming, or most recent past shift
        for (const shift of sortedShifts) {
          const { start, end } = parseShiftTimes(shift.shift_date, shift.start_time, shift.end_time);

          // Check if currently active
          if (now >= start && now <= end) {
            return { sharerId, shift, status: "active", showEarnings };
          }
        }

        // Find next upcoming shift
        for (const shift of sortedShifts) {
          const [hours, minutes] = shift.start_time.split(':').map(Number);
          const shiftDateTime = new Date(shift.shift_date + 'T00:00:00');
          shiftDateTime.setHours(hours, minutes, 0, 0);

          if (shiftDateTime > now) {
            return { sharerId, shift, status: "upcoming", showEarnings };
          }
        }

        // No upcoming shifts, find the most recent past shift
        const pastShifts = sortedShifts.filter(shift => {
          const { end } = parseShiftTimes(shift.shift_date, shift.start_time, shift.end_time);
          return end < now;
        });

        if (pastShifts.length > 0) {
          return { sharerId, shift: pastShifts[pastShifts.length - 1], status: "past", showEarnings };
        }

        return { sharerId, shift: null, status: null, showEarnings };
      } catch (error) {
        logger.error(`Failed to fetch shift preview for sharer ${sharerId}:`, error);
        return { sharerId, shift: null, status: null, showEarnings: false };
      }
    })
  );

  // Sort by shift proximity: active first, then upcoming (soonest), then past (most recent), then no shifts
  return previews.sort((a, b) => {
    // Priority: active > upcoming > past > null
    const statusPriority = { active: 0, upcoming: 1, past: 2, null: 3 };
    const aPriority = statusPriority[a.status ?? "null"];
    const bPriority = statusPriority[b.status ?? "null"];

    if (aPriority !== bPriority) {
      return aPriority - bPriority;
    }

    // Within same status, sort by time
    if (!a.shift || !b.shift) return 0;

    const aStart = new Date(a.shift.shift_date + "T" + a.shift.start_time).getTime();
    const bStart = new Date(b.shift.shift_date + "T" + b.shift.start_time).getTime();

    if (a.status === "upcoming") {
      // Upcoming: soonest first (ascending)
      return aStart - bStart;
    } else if (a.status === "past") {
      // Past: most recent first (descending)
      return bStart - aStart;
    }

    return 0;
  });
}

/**
 * Get shift previews for all sharers (web - uses session auth)
 * Wrapper around getSharerShiftPreviewsWithViewerId that handles authentication
 */
export const getSharerShiftPreviews = cache(
  async (sharerIds: string[]): Promise<SharerShiftPreview[]> => {
    const { user } = await verifySession();
    return getSharerShiftPreviewsWithViewerId(user.id, sharerIds);
  }
);

/**
 * Parse shift times into Date objects, handling cross-midnight shifts
 */
function parseShiftTimes(
  shiftDate: string,
  startTime: string,
  endTime: string
): { start: Date; end: Date } {
  const [startH, startM] = startTime.split(':').map(Number);
  const [endH, endM] = endTime.split(':').map(Number);

  const start = new Date(shiftDate + 'T00:00:00');
  start.setHours(startH, startM, 0, 0);

  const end = new Date(shiftDate + 'T00:00:00');
  end.setHours(endH, endM, 0, 0);

  // Handle cross-midnight: if end <= start, end is next day
  if (end <= start) {
    end.setDate(end.getDate() + 1);
  }

  return { start, end };
}

/**
 * Check if the current user can add more share recipients
 * - Based on subscription tier limits
 */
export const canAddMoreRecipients = cache(
  async (
    userId: string
  ): Promise<{ canAdd: boolean; currentCount: number; limit: number }> => {
    const { user } = await verifySession();

    if (user.id !== userId) {
      throw new Error("User ID mismatch - potential security violation");
    }

    const program = Effect.gen(function* () {
      const sharing = yield* SharingService;
      return yield* sharing.canAddMoreRecipients(userId);
    }).pipe(Effect.provide(SharingLive), Effect.scoped);

    try {
      return await Effect.runPromise(program);
    } catch (error: any) {
      logger.error("Failed to check share capacity:", error);
      return { canAdd: false, currentCount: 0, limit: 0 };
    }
  }
);

/**
 * Internal implementation of getAllFriends
 * @internal - Do not call directly, use getAllFriends()
 */
async function getAllFriendsInternal(userId: string): Promise<Friend[]> {
  "use cache: private";
  cacheTag(`user-${userId}`, "sharing-friends");

  await cookies();

  // Fetch both directions in parallel
  const [allSharersProgram, recipientsProgram] = [
    Effect.gen(function* () {
      const sharing = yield* SharingService;
      return yield* sharing.getAllSharersIncludingBlocked(userId);
    }).pipe(Effect.provide(SharingLive), Effect.scoped),
    Effect.gen(function* () {
      const sharing = yield* SharingService;
      return yield* sharing.getMyShareRecipients(userId);
    }).pipe(Effect.provide(SharingLive), Effect.scoped),
  ];

  try {
    const [allSharers, recipients] = await Promise.all([
      Effect.runPromise(allSharersProgram),
      Effect.runPromise(recipientsProgram),
    ]);

    // Create maps for quick lookup
    const sharerMap = new Map(allSharers.map((s) => [s.id, s]));
    const recipientMap = new Map(recipients.map((r) => [r.id, r]));

    // Collect all unique user IDs
    const allUserIds = new Set([
      ...allSharers.map((s) => s.id),
      ...recipients.map((r) => r.id),
    ]);

    // Build unified friends list
    const friends: Friend[] = [];

    for (const id of allUserIds) {
      const sharer = sharerMap.get(id);
      const recipient = recipientMap.get(id);

      // Use whichever has the user info (prefer sharer since it has blocked info)
      const userInfo = sharer ?? recipient;
      if (!userInfo) continue;

      friends.push({
        id,
        email: userInfo.email,
        phone: userInfo.phone,
        firstName: userInfo.firstName,
        profilePictureUrl: userInfo.profilePictureUrl,
        oauthAvatarUrl: userInfo.oauthAvatarUrl,
        sharesWithMe: sharer
          ? {
              blocked: sharer.blocked,
              showEarningsToMe: sharer.showEarnings,
              sharedAt: sharer.sharedAt,
              notificationFrequency: sharer.notificationFrequency,
            }
          : null,
        iShareWith: recipient
          ? {
              showEarningsToThem: recipient.showEarnings,
              sharedAt: recipient.sharedAt,
            }
          : null,
      });
    }

    // Sort alphabetically by name (firstName, then email, then phone)
    // Use Norwegian locale to correctly sort Æ, Ø, Å after Z
    friends.sort((a, b) => {
      const aName = (a.firstName || a.email || a.phone || "").toLowerCase();
      const bName = (b.firstName || b.email || b.phone || "").toLowerCase();
      return aName.localeCompare(bName, "nb");
    });

    return friends;
  } catch (error: any) {
    logger.error("Failed to fetch all friends:", error);
    return [];
  }
}

/**
 * Get unified friends list combining both directions of sharing
 * - People who share their shifts with me (sharers)
 * - People I share my shifts with (recipients)
 * - Uses React cache() for request deduplication
 *
 * Promise wrapper around Effect-based SharingService
 */
export const getAllFriends = cache(
  async (userId: string): Promise<Friend[]> => {
    const { user } = await verifySession();

    if (user.id !== userId) {
      throw new Error("User ID mismatch - potential security violation");
    }

    return getAllFriendsInternal(userId);
  }
);

/**
 * Block a sharer (hide their shifts from viewer's list)
 * - Only affects the viewer's view, the share relationship persists
 *
 * Promise wrapper around Effect-based SharingService
 */
export async function blockSharer(ownerId: string): Promise<void> {
  const { user } = await verifySession();

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.blockSharer(user.id, ownerId);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  await Effect.runPromise(program);
}

/**
 * Unblock a sharer (restore their shifts to viewer's list)
 * - Reverses a previous block action
 *
 * Promise wrapper around Effect-based SharingService
 */
export async function unblockSharer(ownerId: string): Promise<void> {
  const { user } = await verifySession();

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.unblockSharer(user.id, ownerId);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  await Effect.runPromise(program);
}

/**
 * Internal implementation of getBlockedSharers
 * @internal - Do not call directly, use getBlockedSharers()
 */
async function getBlockedSharersInternal(
  userId: string
): Promise<SharedUser[]> {
  "use cache: private";
  cacheTag(`user-${userId}`, "sharing-blocked");

  await cookies();

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    const data = yield* sharing.getBlockedSharers(userId);
    return data;
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);
    return [...result];
  } catch (error: any) {
    logger.error("Failed to fetch blocked sharers:", error);
    return [];
  }
}

/**
 * Get blocked sharers for the current user
 * - Uses React cache() for request deduplication
 * - Cache is scoped by userId
 *
 * Promise wrapper around Effect-based SharingService
 */
export const getBlockedSharers = cache(
  async (userId: string): Promise<SharedUser[]> => {
    const { user } = await verifySession();

    if (user.id !== userId) {
      throw new Error("User ID mismatch - potential security violation");
    }

    return getBlockedSharersInternal(userId);
  }
);

/**
 * Update notification frequency for a specific sharer
 * - Controls how often you receive notifications about this sharer's shifts
 * - Options: instant, summary (daily digest), or muted (no notifications)
 *
 * Promise wrapper around Effect-based SharingService
 */
export async function updateNotificationFrequency(
  ownerId: string,
  frequency: NotificationFrequency
): Promise<{ success: boolean; error?: string }> {
  const { user } = await verifySession();

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.updateNotificationFrequency(user.id, ownerId, frequency);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);
    return { success: true };
  } catch (error: any) {
    logger.error("Failed to update notification frequency:", error);
    return { success: false, error: "Failed to update notification frequency" };
  }
}
