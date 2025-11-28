/**
 * Tool Executor
 *
 * Executes chat tools with validation, authentication, and retry logic
 */

import { createShifts } from "@/app/[locale]/(app)/shifts/add/actions";
import { updateShift } from "@/app/[locale]/(app)/shifts/_actions/updateShift";
import { deleteShift } from "@/app/[locale]/(app)/shifts/_actions/deleteShift";
import { getComputedShiftsForApi } from "@/data-access/shifts";
import { draftRecurringShift } from "@/app/[locale]/(app)/shifts/add/_actions/draftRecurringShift";
import { createRecurringShift } from "@/app/[locale]/(app)/shifts/add/_actions/createRecurringShift";
import { updateRecurringShift } from "@/app/[locale]/(app)/shifts/_actions/updateRecurringShift";
import { deleteRecurringShift } from "@/app/[locale]/(app)/shifts/_actions/deleteRecurringShift";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { EndCondition } from "@/lib/recurring/types";
import type { BreakMethod } from "@/lib/payroll/types";
import type {
  ToolName,
  ToolResult,
  ManageShiftInput,
  QueryShiftsInput,
  CalculateWagesInput,
  DraftRecurringShiftInput,
  ConfirmRecurringShiftInput,
  ManageRecurringShiftInput,
  ManageRecurringExclusionInput,
  GetStatisticsInput,
  ManageSettingsInput,
  CalculateEarningsInput,
} from "./tools";
import {
  manageShiftSchema,
  queryShiftsSchema,
  calculateWagesSchema,
  draftRecurringShiftSchema,
  confirmRecurringShiftSchema,
  manageRecurringShiftSchema,
  manageRecurringExclusionSchema,
  getStatisticsSchema,
  manageSettingsSchema,
  calculateEarningsSchema,
} from "./tools";
import { getStatsDataForApi } from "@/data-access/stats";
import { SettingsService } from "@/lib/services/settings";
import { AuthSettingsLive } from "@/lib/layers/app";
import { Effect } from "effect";
import { logger } from "@/lib/logger";
import { getDictionary } from "@/lib/i18n/dictionaries";
import { defaultLocale, type Locale } from "@/lib/i18n/config";

// Type for tool result translations
type ToolResultTranslations = ReturnType<typeof getDictionary>['pages']['wagey']['toolResults'];

// Helper to interpolate translation strings
function t(template: string, params: Record<string, string | number> = {}): string {
  return template.replace(/{(\w+)}/g, (_, key) => String(params[key] ?? `{${key}}`));
}

// =============================================================================
// USER SETTINGS HELPERS
// =============================================================================

/**
 * Get user's selected currency (defaults to NOK if not set)
 */
async function getUserCurrency(userId: string): Promise<string> {
  const program = Effect.gen(function* () {
    const settingsService = yield* SettingsService;
    const settings = yield* settingsService.getUserSettings(userId);
    return settings?.currency || "NOK";
  }).pipe(
    Effect.provide(AuthSettingsLive),
    Effect.catchAll(() => Effect.succeed("NOK")),
    Effect.scoped
  );

  return Effect.runPromise(program);
}

// =============================================================================
// SHORT ID UTILITIES
// =============================================================================

/**
 * Convert a full UUID to a 5-character short ID.
 * Uses first 5 chars of UUID (65k+ combinations, virtually no collision risk per user).
 */
function toShortId(uuid: string): string {
  return uuid.slice(0, 5);
}

/**
 * Check if a string looks like a short ID (5 hex chars) vs a full UUID.
 */
function isShortId(id: string): boolean {
  return /^[a-f0-9]{4,8}$/i.test(id) && !id.includes("-");
}

/**
 * Resolve a short ID to full UUID using pre-fetched shifts.
 * Returns the full UUID if found, or null if not found/ambiguous.
 *
 * Handles both regular shifts (short hex IDs) and virtual shifts:
 * - Regular: "a1b2c" -> "a1b2c3d4-e5f6-..."
 * - Virtual: "virtual-a1b2c-2025-12-03" -> "virtual-a1b2c3d4-e5f6-...-2025-12-03"
 */
function resolveShortIdFromShifts(
  shortOrFullId: string,
  shifts: { id: string }[]
): string | null {
  // Handle virtual shift short IDs: virtual-{short_recurring_id}-{date}
  if (shortOrFullId.startsWith("virtual-")) {
    const parts = shortOrFullId.split("-");
    // Format: virtual-{5char}-YYYY-MM-DD -> ["virtual", "a1b2c", "2025", "12", "03"]
    if (parts.length === 5) {
      const shortRecurringId = parts[1];
      const date = `${parts[2]}-${parts[3]}-${parts[4]}`;

      // Find virtual shift where recurring_id starts with shortRecurringId and date matches
      const matches = shifts.filter((s) => {
        if (!s.id.startsWith("virtual-")) return false;
        // Full format: virtual-{uuid}-{date}
        const fullParts = s.id.split("-");
        const fullRecurringId = fullParts.slice(1, 6).join("-");
        const fullDate = fullParts.slice(6).join("-");
        return (
          fullRecurringId.toLowerCase().startsWith(shortRecurringId.toLowerCase()) &&
          fullDate === date
        );
      });

      if (matches.length === 1) {
        return matches[0].id;
      }
      return null;
    }
    // If it's a full virtual ID, return as-is
    return shortOrFullId;
  }

  // If it's already a full UUID, return as-is
  if (!isShortId(shortOrFullId)) {
    return shortOrFullId;
  }

  // Regular shift: match by prefix
  const matches = shifts.filter((s) =>
    s.id.toLowerCase().startsWith(shortOrFullId.toLowerCase())
  );

  if (matches.length === 1) {
    return matches[0].id;
  }

  // Ambiguous (multiple matches) or not found
  return null;
}

/**
 * Resolve multiple short IDs to full UUIDs using pre-fetched shifts.
 * Returns array of resolved IDs (nulls filtered out).
 */
function resolveShortIdsFromShifts(
  shortOrFullIds: string[],
  shifts: { id: string }[]
): string[] {
  return shortOrFullIds
    .map((id) => resolveShortIdFromShifts(id, shifts))
    .filter((id): id is string => id !== null);
}

/**
 * Resolve a short recurring shift ID to full UUID by prefix matching.
 * Returns the full UUID if found, or null if not found/ambiguous.
 */
async function resolveRecurringId(
  shortOrFullId: string,
  userId: string
): Promise<string | null> {
  // If it's already a full UUID, return as-is
  if (!isShortId(shortOrFullId)) {
    return shortOrFullId;
  }

  // Fetch user's recurring shifts and find by prefix
  const supabase = await createSupabaseServerClient();
  const { data: recurring } = await supabase
    .from("recurring_shifts")
    .select("id")
    .eq("user_id", userId);

  if (!recurring) return null;

  const matches = recurring.filter((r) =>
    r.id.toLowerCase().startsWith(shortOrFullId.toLowerCase())
  );

  if (matches.length === 1) {
    return matches[0].id;
  }

  // Ambiguous (multiple matches) or not found
  return null;
}

/**
 * Execute a tool call with retry logic
 */
const KNOWN_TOOL_NAMES: ToolName[] = [
  "manage_shift",
  "query_shifts",
  "calculate_wages",
  "draft_recurring_shift",
  "confirm_recurring_shift",
  "manage_recurring_shift",
  "manage_recurring_exclusion",
  "get_statistics",
  "manage_settings",
  "calculate_earnings",
];

function normalizeToolName(toolName: string): ToolName | null {
  const trimmed = toolName.trim();

  if (KNOWN_TOOL_NAMES.includes(trimmed as ToolName)) {
    return trimmed as ToolName;
  }

  const fuzzyMatch = KNOWN_TOOL_NAMES.find((name) =>
    trimmed.replace(/\s+/g, "").includes(name)
  );

  return fuzzyMatch ?? null;
}

export async function executeTool(
  toolName: string,
  argumentsJson: string,
  userId: string,
  locale: Locale = defaultLocale
): Promise<ToolResult> {
  console.log("[executeTool] Called with tool:", toolName, "userId:", userId, "locale:", locale);
  console.log("[executeTool] Arguments JSON:", argumentsJson);

  // Load translations once at start
  const dict = getDictionary(locale);
  const tr = dict.pages.wagey.toolResults;

  try {
    const normalizedToolName = normalizeToolName(toolName);

    if (!normalizedToolName) {
      console.error("[executeTool] Unknown tool:", toolName);
      return {
        success: false,
        message: t(tr.unknownTool, { name: toolName }),
      };
    }

    console.log("[executeTool] Normalized tool name:", normalizedToolName);

    // Parse arguments - handle empty string as empty object
    const trimmedArgs = argumentsJson.trim();
    const args = trimmedArgs === "" ? {} : JSON.parse(trimmedArgs);
    console.log("[executeTool] Parsed arguments:", args);

    // Execute tool with retry (once)
    let attempt = 0;
    let lastError: Error | null = null;

    while (attempt < 2) {
      try {
        console.log("[executeTool] Attempting execution, attempt:", attempt + 1);
        const result = await executeToolOnce(normalizedToolName, args, userId, tr);
        console.log("[executeTool] Execution successful:", result.success);
        return result;
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        console.error("[executeTool] Execution failed, attempt:", attempt + 1, "error:", lastError.message);
        attempt++;

        if (attempt < 2) {
          console.log("[executeTool] Retrying in 500ms...");
          // Wait 500ms before retry
          await new Promise((resolve) => setTimeout(resolve, 500));
        }
      }
    }

    // All attempts failed
    console.error("[executeTool] All attempts failed");
    return {
      success: false,
      message: t(tr.failedAfterAttempts, { count: attempt, error: lastError?.message || "Unknown error" }),
    };
  } catch (error) {
    console.error("[executeTool] Error parsing arguments:", error);
    return {
      success: false,
      message: t(tr.failedToParseArgs, { error: error instanceof Error ? error.message : "Unknown error" }),
    };
  }
}

/**
 * Execute tool once (no retry)
 */
async function executeToolOnce(
  toolName: ToolName,
  args: unknown,
  userId: string,
  tr: ToolResultTranslations
): Promise<ToolResult> {
  switch (toolName) {
    case "manage_shift":
      return await executeManageShift(args, userId, tr);

    case "query_shifts":
      return await executeQueryShifts(args, userId, tr);

    case "calculate_wages":
      return await executeCalculateWages(args, userId, tr);

    case "draft_recurring_shift":
      return await executeDraftRecurringShift(args, userId, tr);

    case "confirm_recurring_shift":
      return await executeConfirmRecurringShift(args, userId, tr);

    case "manage_recurring_shift":
      return await executeManageRecurringShift(args, userId, tr);

    case "manage_recurring_exclusion":
      return await executeManageRecurringExclusion(args, userId, tr);

    case "get_statistics":
      return await executeGetStatistics(args, userId, tr);

    case "manage_settings":
      return await executeManageSettings(args, userId, tr);

    case "calculate_earnings":
      return await executeCalculateEarnings(args, userId, tr);

    default:
      return {
        success: false,
        message: t(tr.unknownTool, { name: toolName }),
      };
  }
}

/**
 * Execute manage_shift tool (consolidated CRUD)
 */
async function executeManageShift(
  args: unknown,
  userId: string,
  tr: ToolResultTranslations
): Promise<ToolResult> {
  const parsed = manageShiftSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }),
    };
  }

  const input: ManageShiftInput = parsed.data;

  try {
    switch (input.action) {
      case "create": {
        if (!input.dates || !input.start || !input.end) {
          return {
            success: false,
            message: t(tr.missingFields, { fields: "dates, start, end" }),
          };
        }

        const result = await createShifts({
          dates: input.dates,
          start: input.start,
          end: input.end,
        });

        return {
          success: true,
          message: result.inserted === 1
            ? t(tr.createdShift, { count: result.inserted })
            : t(tr.createdShifts, { count: result.inserted }),
          data: result,
        };
      }

      case "update": {
        if (!input.shiftId) {
          return {
            success: false,
            message: tr.missingShiftId,
          };
        }

        // At least one field must be updated
        if (!input.date && !input.start && !input.end) {
          return {
            success: false,
            message: tr.mustProvideDateStartEnd,
          };
        }

        // Fetch shifts once for both ID resolution and getting shift details
        const shiftsResult = await getComputedShiftsForApi(userId, { limit: 1000 });
        const fullShiftId = resolveShortIdFromShifts(input.shiftId, shiftsResult.shifts);
        if (!fullShiftId) {
          return {
            success: false,
            message: t(tr.shiftNotFound, { id: input.shiftId }),
          };
        }

        const shift = shiftsResult.shifts.find((s) => s.id === fullShiftId);
        if (!shift) {
          return {
            success: false,
            message: t(tr.shiftNotFound, { id: input.shiftId }),
          };
        }

        const updatedDate = input.date || shift.shift_date;

        await updateShift({
          id: fullShiftId,
          shift_date: updatedDate,
          start: input.start || shift.start_time,
          end: input.end || shift.end_time,
        });

        return {
          success: true,
          message: t(tr.updatedShift, { date: formatDateCompact(updatedDate, tr) }),
        };
      }

      case "delete": {
        // Fetch shifts once for ID resolution and display info
        const shiftsResult = await getComputedShiftsForApi(userId, { limit: 1000 });

        // Support both single and bulk delete
        if (input.shiftIds && input.shiftIds.length > 0) {
          // Resolve short IDs to full UUIDs
          const fullShiftIds = resolveShortIdsFromShifts(input.shiftIds, shiftsResult.shifts);
          if (fullShiftIds.length === 0) {
            return {
              success: false,
              message: tr.noShiftsWithIds,
            };
          }

          await Promise.all(fullShiftIds.map((id) => deleteShift(id)));

          return {
            success: true,
            message: fullShiftIds.length === 1
              ? t(tr.deletedShift, { date: "" }).replace(" on ", "").replace(" den ", "") // Single shift without date
              : t(tr.deletedShifts, { count: fullShiftIds.length }),
          };
        } else if (input.shiftId) {
          // Resolve short ID to full UUID
          const fullShiftId = resolveShortIdFromShifts(input.shiftId, shiftsResult.shifts);
          if (!fullShiftId) {
            return {
              success: false,
              message: t(tr.shiftNotFound, { id: input.shiftId }),
            };
          }

          const shift = shiftsResult.shifts.find((s) => s.id === fullShiftId);
          await deleteShift(fullShiftId);

          return {
            success: true,
            message: t(tr.deletedShift, { date: shift ? formatDateCompact(shift.shift_date, tr) : tr.unknownDate }),
          };
        } else {
          return {
            success: false,
            message: tr.missingShiftIdOrIds,
          };
        }
      }

      default:
        return {
          success: false,
          message: t(tr.unknownAction, { action: input.action }),
        };
    }
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Failed to execute shift operation"
    );
  }
}

/**
 * Get English weekday abbreviation from ISO date (for AI consumption)
 */
function getWeekdayAbbr(isoDate: string, _tr: ToolResultTranslations): string {
  const date = new Date(isoDate + "T12:00:00"); // Noon to avoid timezone issues
  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return weekdays[date.getDay()];
}

/**
 * Format ISO date as compact "26 Jan" format for messages (localized)
 */
function formatDateCompact(isoDate: string, tr: ToolResultTranslations): string {
  const date = new Date(isoDate + "T12:00:00"); // Noon to avoid timezone issues
  const day = date.getDate();
  const monthKeys = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"] as const;
  return `${day} ${tr.months[monthKeys[date.getMonth()]]}`;
}

/**
 * Format recurring shift as readable description (e.g., "Mon/Wed 09:00-17:00") (localized)
 */
function formatRecurringDescription(
  recurring: {
    selected_days?: Record<string, string>;
    start_time: string;
    end_time: string;
  },
  tr: ToolResultTranslations
): string {
  const weekdayKeys = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"] as const;
  const selectedDays = recurring.selected_days || {};

  // Get sorted day numbers
  const dayNums = Object.keys(selectedDays)
    .map(Number)
    .sort((a, b) => a - b);

  // Format days using localized abbreviations
  const daysStr = dayNums.map(d => tr.weekdays[weekdayKeys[d]]).join("/");

  // Parse times to HH:mm
  const parseTime = (time: string): string => {
    const match = time?.match(/^(\d{2}:\d{2})/);
    return match ? match[1] : time;
  };

  return `${daysStr} ${parseTime(recurring.start_time)}-${parseTime(recurring.end_time)}`;
}

/**
 * Execute query_shifts tool (enhanced with filters)
 */
async function executeQueryShifts(
  args: unknown,
  userId: string,
  tr: ToolResultTranslations
): Promise<ToolResult> {
  const parsed = queryShiftsSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: t(tr.invalidInput, { details: parsed.error.issues.map((i: any) => i.message).join(", ") }),
    };
  }

  const input: QueryShiftsInput = parsed.data;

  const getCurrentWeekRange = () => {
    const now = new Date();
    const day = now.getDay();
    const diffToMonday = day === 0 ? -6 : 1 - day; // Monday = 1, Sunday = 0

    const start = new Date(now);
    start.setHours(0, 0, 0, 0);
    start.setDate(now.getDate() + diffToMonday);

    const end = new Date(start);
    end.setDate(start.getDate() + 6);

    // Use local date to avoid UTC offset shifting the day (e.g., 17. becomes 16. UTC)
    const toLocalIsoDate = (d: Date) =>
      d.toLocaleDateString("sv-SE"); // sv-SE gives YYYY-MM-DD in local time

    return {
      startDate: toLocalIsoDate(start),
      endDate: toLocalIsoDate(end),
    };
  };

  const weekRange = getCurrentWeekRange();

  try {
    const result = await getComputedShiftsForApi(userId, {
      startDate: input.startDate ?? weekRange.startDate,
      endDate: input.endDate ?? weekRange.endDate,
      limit: 1000, // Fetch more to allow client-side filtering
    });

    let filteredShifts = result.shifts;

    // Apply time filters
    if (input.minTime) {
      filteredShifts = filteredShifts.filter(shift => shift.start_time >= input.minTime!);
    }
    if (input.maxTime) {
      filteredShifts = filteredShifts.filter(shift => shift.start_time <= input.maxTime!);
    }

    // Apply weekday filter
    if (input.weekdays && input.weekdays.length > 0) {
      filteredShifts = filteredShifts.filter(shift => {
        const date = new Date(shift.shift_date + "T12:00:00");
        const weekday = date.getDay();
        return input.weekdays!.includes(weekday);
      });
    }

    // Sort shifts
    if (input.sortBy === "earnings") {
      filteredShifts = filteredShifts.sort((a, b) => b.computed.gross - a.computed.gross);
    } else if (input.sortBy === "hours") {
      filteredShifts = filteredShifts.sort((a, b) => b.computed.paidHours - a.computed.paidHours);
    }
    // Default sort by date is already handled by DAL

    // Apply limit after filtering
    const limitedShifts = filteredShifts.slice(0, input.limit || 30);

    // Get user's currency
    const currency = await getUserCurrency(userId);

    // Check if user has tax deduction enabled
    const hasTaxDeduction = result.settings.tax_deduction_enabled && result.settings.tax_percentage;

    // Format shifts for AI - compact format to reduce tokens
    const shiftsFormatted = limitedShifts.map((shift) => {
      const gross = Number(shift.computed.gross.toFixed(2));
      // For virtual shifts, use compact format: virtual-{short_recurring_id}-{date}
      // For regular shifts, use short 5-char ID for token efficiency
      let shiftId: string;
      if (shift.id.startsWith("virtual-")) {
        // Extract recurring_id from virtual-{recurring_id}-{date} and truncate it
        const parts = shift.id.split("-");
        // parts: ["virtual", ...uuid_parts..., "YYYY", "MM", "DD"]
        // UUID is parts[1] through parts[5], date is parts[6], parts[7], parts[8]
        const recurringId = parts.slice(1, 6).join("-"); // Full UUID
        const date = parts.slice(6).join("-"); // YYYY-MM-DD
        shiftId = `virtual-${toShortId(recurringId)}-${date}`;
      } else {
        shiftId = toShortId(shift.id);
      }
      const base = {
        id: shiftId,
        date: shift.shift_date,
        day: getWeekdayAbbr(shift.shift_date, tr),
        start: shift.start_time,
        end: shift.end_time,
        hours: Number(shift.computed.paidHours.toFixed(2)),
        gross,
      };

      // Only include net if tax deduction is enabled
      if (hasTaxDeduction) {
        return {
          ...base,
          net: Number(calculateNetPay(shift.computed.gross, result.settings, shift.shift_date).toFixed(2)),
        };
      }

      return base;
    });

    // Calculate summary statistics for the filtered shifts
    const totalHours = limitedShifts.reduce((sum, s) => sum + s.computed.paidHours, 0);
    const totalGross = limitedShifts.reduce((sum, s) => sum + s.computed.gross, 0);
    const totalNet = limitedShifts.reduce((sum, s) => {
      const net = calculateNetPay(s.computed.gross, result.settings, s.shift_date);
      return sum + net;
    }, 0);
    const shiftCount = limitedShifts.length;

    const summary = {
      shiftCount,
      totalHours: Number(totalHours.toFixed(2)),
      totalGross: Number(totalGross.toFixed(2)),
      totalNet: Number(totalNet.toFixed(2)),
      avgHoursPerShift: shiftCount > 0 ? Number((totalHours / shiftCount).toFixed(2)) : 0,
      avgGrossPerShift: shiftCount > 0 ? Number((totalGross / shiftCount).toFixed(2)) : 0,
    };

    return {
      success: true,
      message: shiftsFormatted.length === 1
        ? t(tr.foundShift, { count: shiftsFormatted.length })
        : t(tr.foundShifts, { count: shiftsFormatted.length }),
      data: shiftsFormatted,
      summary,
      currency,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Failed to fetch shifts"
    );
  }
}

/**
 * Calculate net pay after tax deduction
 */
function calculateNetPay(
  gross: number,
  settings: { tax_deduction_enabled?: boolean | null; tax_percentage?: number | null; half_tax_month?: number | null },
  shiftDate: string
): number {
  if (!settings.tax_deduction_enabled || !settings.tax_percentage) {
    return gross; // No tax deduction
  }

  let taxRate = settings.tax_percentage / 100;

  // Check if this is a half-tax month
  if (settings.half_tax_month) {
    const shiftMonth = new Date(shiftDate + "T12:00:00").getMonth() + 1; // 1-12
    if (shiftMonth === settings.half_tax_month) {
      taxRate = taxRate / 2;
    }
  }

  const taxAmount = gross * taxRate;
  return gross - taxAmount;
}

/**
 * Execute calculate_wages tool (date range only)
 */
async function executeCalculateWages(
  args: unknown,
  userId: string,
  tr: ToolResultTranslations
): Promise<ToolResult> {
  const parsed = calculateWagesSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: t(tr.invalidInput, { details: parsed.error.issues.map((i: any) => i.message).join(", ") }),
    };
  }

  const input: CalculateWagesInput = parsed.data;

  try {
    // Fetch shifts by date range
    const result = await getComputedShiftsForApi(userId, {
      startDate: input.startDate,
      endDate: input.endDate,
      limit: 1000,
    });

    const shifts = result.shifts;
    const settings = result.settings;

    // Get user's currency
    const currency = await getUserCurrency(userId);

    // Handle case where no shifts found
    if (shifts.length === 0) {
      const periodDesc = input.startDate === input.endDate
        ? input.startDate
        : `${input.startDate} - ${input.endDate}`;

      return {
        success: true,
        message: t(tr.noShiftsFound, { period: periodDesc }),
        data: {
          totalShifts: 0,
          totalHours: 0,
          totalGross: 0,
          totalNet: 0,
          taxDeducted: 0,
        },
        currency,
      };
    }

    // Calculate totals
    const totalHours = shifts.reduce((sum, s) => sum + s.computed.paidHours, 0);
    const totalGross = shifts.reduce((sum, s) => sum + s.computed.gross, 0);

    // Calculate net pay for each shift and sum them up
    const totalNet = shifts.reduce((sum, s) => {
      const net = calculateNetPay(s.computed.gross, settings, s.shift_date);
      return sum + net;
    }, 0);

    const totalTaxDeducted = totalGross - totalNet;

    return {
      success: true,
      message: shifts.length === 1
        ? t(tr.calculatedWages, { count: 1 }).replace("shifts", "shift")
        : t(tr.calculatedWages, { count: shifts.length }),
      data: {
        totalShifts: shifts.length,
        totalHours: Number(totalHours.toFixed(2)),
        totalGross: Number(totalGross.toFixed(2)),
        totalNet: Number(totalNet.toFixed(2)),
        taxDeducted: Number(totalTaxDeducted.toFixed(2)),
      },
      currency,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Failed to calculate wages"
    );
  }
}

/**
 * Convert simplified frequency to repeat_interval_weeks
 */
function frequencyToIntervalWeeks(frequency: string): 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 {
  switch (frequency) {
    case "weekly": return 0;
    case "biweekly": return 1;
    case "every_3_weeks": return 2;
    case "every_4_weeks": return 3;
    default: return 0;
  }
}

/**
 * Convert simplified endType/endValue to EndCondition
 */
function convertEndCondition(endType: string, endValue?: number | string): EndCondition {
  switch (endType) {
    case "never":
      return null;
    case "after_months":
      return { type: "months", value: typeof endValue === "number" ? endValue : 1 };
    case "after_years":
      return { type: "years", value: typeof endValue === "number" ? endValue : 1 };
    case "on_date":
      return {
        type: "end_date",
        date: typeof endValue === "string" ? endValue : "",
        end_time: "23:59:59",
      };
    default:
      return null;
  }
}

/**
 * Convert weekdays array to selected_days object
 */
function weekdaysArrayToSelectedDays(
  weekdays: Array<{ day: number; anchorDate: string }>
): Record<'0' | '1' | '2' | '3' | '4' | '5' | '6', string> {
  return weekdays.reduce((acc, { day, anchorDate }) => {
    acc[String(day) as '0' | '1' | '2' | '3' | '4' | '5' | '6'] = anchorDate;
    return acc;
  }, {} as Record<'0' | '1' | '2' | '3' | '4' | '5' | '6', string>);
}

/**
 * Execute draft_recurring_shift tool (Step 1 of 2)
 */
async function executeDraftRecurringShift(
  args: unknown,
  _userId: string,
  tr: ToolResultTranslations
): Promise<ToolResult> {
  const parsed = draftRecurringShiftSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }),
    };
  }

  const input: DraftRecurringShiftInput = parsed.data;

  // Convert weekdays array to selected_days object (supports multiple weekdays)
  const selectedDays = weekdaysArrayToSelectedDays(input.weekdays);
  const repeatIntervalWeeks = frequencyToIntervalWeeks(input.frequency);
  const endCondition = convertEndCondition(input.endType, input.endValue);

  try {
    const result = await draftRecurringShift({
      selected_days: selectedDays,
      start_time: input.start,
      end_time: input.end,
      repeat_interval_weeks: repeatIntervalWeeks,
      end_condition: endCondition,
      exclusions: [],
    });

    if (result.conflictCount === 0) {
      return {
        success: true,
        message: t(tr.validatedRecurring, { count: result.projectedShiftCount }),
        data: result,
      };
    }

    return {
      success: true,
      message: t(tr.validatedRecurringConflicts, { count: result.projectedShiftCount, conflicts: result.conflictCount }),
      data: result,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Failed to validate recurring shift"
    );
  }
}

/**
 * Execute confirm_recurring_shift tool (Step 2 of 2)
 */
async function executeConfirmRecurringShift(
  args: unknown,
  _userId: string,
  tr: ToolResultTranslations
): Promise<ToolResult> {
  const parsed = confirmRecurringShiftSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }),
    };
  }

  const input: ConfirmRecurringShiftInput = parsed.data;

  // Convert weekdays array to selected_days object (supports multiple weekdays)
  const selectedDays = weekdaysArrayToSelectedDays(input.weekdays);
  const repeatIntervalWeeks = frequencyToIntervalWeeks(input.frequency);
  const endCondition = convertEndCondition(input.endType, input.endValue);

  // Map new conflict resolution names to old ones
  const conflictResolution = input.conflictResolution === "skip_conflicts" ? "exclude_conflicts" : "keep_existing";

  try {
    const result = await createRecurringShift(
      {
        selected_days: selectedDays,
        start_time: input.start,
        end_time: input.end,
        repeat_interval_weeks: repeatIntervalWeeks,
        end_condition: endCondition,
        exclusions: [],
      },
      {
        conflictResolution,
      }
    );

    return {
      success: true,
      message: input.conflictResolution === "skip_conflicts" ? tr.recurringCreatedSkipped : tr.recurringCreatedKept,
      data: result,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Failed to create recurring shift"
    );
  }
}

/**
 * Convert interval weeks back to frequency string
 */
function intervalWeeksToFrequency(intervalWeeks: number): string {
  switch (intervalWeeks) {
    case 0: return "weekly";
    case 1: return "biweekly";
    case 2: return "every_3_weeks";
    case 3: return "every_4_weeks";
    default: return "weekly";
  }
}

/**
 * Convert database end_condition to simplified format for AI
 */
function formatEndConditionForAI(endCondition: EndCondition): { endType: string; endValue?: number | string } {
  if (endCondition === null) {
    return { endType: "never" };
  }
  switch (endCondition.type) {
    case "months":
      return { endType: "after_months", endValue: endCondition.value };
    case "years":
      return { endType: "after_years", endValue: endCondition.value };
    case "end_date":
      return { endType: "on_date", endValue: endCondition.date };
    default:
      return { endType: "never" };
  }
}

/**
 * Format recurring shift data for AI consumption
 */
function formatRecurringForAI(recurring: any): any {
  const selectedDays = recurring.selected_days || {};

  // Convert selected_days object to weekdays array format
  const weekdays = Object.entries(selectedDays)
    .map(([day, anchorDate]) => ({
      day: Number(day),
      anchorDate: anchorDate as string,
    }))
    .sort((a, b) => a.day - b.day); // Sort by day number

  // Parse times to HH:mm format
  const parseTime = (time: string): string => {
    const match = time?.match(/^(\d{2}:\d{2})/);
    return match ? match[1] : time;
  };

  const { endType, endValue } = formatEndConditionForAI(recurring.end_condition as EndCondition);

  return {
    recurringId: toShortId(recurring.id), // Use short ID to reduce tokens
    weekdays, // Array of {day, anchorDate} objects (supports multiple weekdays)
    start: parseTime(recurring.start_time),
    end: parseTime(recurring.end_time),
    frequency: intervalWeeksToFrequency(recurring.repeat_interval_weeks),
    endType,
    endValue,
    exclusions: recurring.exclusions || [],
    createdAt: recurring.created_at,
  };
}

/**
 * Execute manage_recurring_shift tool (consolidated update/delete/list)
 */
async function executeManageRecurringShift(
  args: unknown,
  _userId: string,
  tr: ToolResultTranslations
): Promise<ToolResult> {
  const parsed = manageRecurringShiftSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }),
    };
  }

  const input: ManageRecurringShiftInput = parsed.data;

  try {
    switch (input.action) {
      case "update": {
        if (!input.recurringId) {
          return {
            success: false,
            message: tr.missingRecurringId,
          };
        }

        // At least one field must be updated
        if (
          input.weekdays === undefined &&
          !input.start &&
          !input.end &&
          input.frequency === undefined &&
          input.endType === undefined
        ) {
          return {
            success: false,
            message: tr.mustProvideField,
          };
        }

        // Resolve short ID to full UUID
        const fullRecurringId = await resolveRecurringId(input.recurringId, _userId);
        if (!fullRecurringId) {
          return {
            success: false,
            message: t(tr.recurringNotFound, { id: input.recurringId }),
          };
        }

        const supabase = await createSupabaseServerClient();

        // Fetch current recurring shift to merge with updates
        const { data: currentRecurring, error: fetchError } = await supabase
          .from("recurring_shifts")
          .select("*")
          .eq("id", fullRecurringId)
          .eq("user_id", _userId)
          .single();

        if (fetchError || !currentRecurring) {
          return {
            success: false,
            message: t(tr.recurringNotFound, { id: input.recurringId }),
          };
        }

        // Parse times to HH:mm format (remove timezone if present)
        const parseTime = (time: string): string => {
          const match = time.match(/^(\d{2}:\d{2})/);
          return match ? match[1] : time;
        };

        // Build selected_days - either from new weekdays array or keep existing
        let selectedDays: Record<'0' | '1' | '2' | '3' | '4' | '5' | '6', string>;
        if (input.weekdays !== undefined) {
          selectedDays = weekdaysArrayToSelectedDays(input.weekdays);
        } else {
          selectedDays = currentRecurring.selected_days as Record<'0' | '1' | '2' | '3' | '4' | '5' | '6', string>;
        }

        // Build end_condition - either from new input or keep existing
        let endCondition: EndCondition;
        if (input.endType !== undefined) {
          endCondition = convertEndCondition(input.endType, input.endValue);
        } else {
          endCondition = currentRecurring.end_condition as EndCondition;
        }

        // Build repeat_interval_weeks
        const repeatIntervalWeeks = input.frequency !== undefined
          ? frequencyToIntervalWeeks(input.frequency)
          : (currentRecurring.repeat_interval_weeks as 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8);

        const updatedStartTime = input.start ?? parseTime(currentRecurring.start_time);
        const updatedEndTime = input.end ?? parseTime(currentRecurring.end_time);

        await updateRecurringShift({
          id: fullRecurringId,
          selected_days: selectedDays,
          start_time: updatedStartTime,
          end_time: updatedEndTime,
          repeat_interval_weeks: repeatIntervalWeeks,
          end_condition: endCondition,
          exclusions: currentRecurring.exclusions || [],
        });

        return {
          success: true,
          message: t(tr.updatedRecurring, { description: formatRecurringDescription({
            selected_days: selectedDays,
            start_time: updatedStartTime,
            end_time: updatedEndTime,
          }, tr) }),
        };
      }

      case "delete": {
        if (!input.recurringId) {
          return {
            success: false,
            message: tr.missingRecurringId,
          };
        }

        // Resolve short ID to full UUID
        const fullRecurringId = await resolveRecurringId(input.recurringId, _userId);
        if (!fullRecurringId) {
          return {
            success: false,
            message: t(tr.recurringNotFound, { id: input.recurringId }),
          };
        }

        // Fetch recurring shift info for the message before deleting
        const supabaseForDelete = await createSupabaseServerClient();
        const { data: recurringToDelete } = await supabaseForDelete
          .from("recurring_shifts")
          .select("selected_days, start_time, end_time")
          .eq("id", fullRecurringId)
          .eq("user_id", _userId)
          .single();

        await deleteRecurringShift(fullRecurringId);

        const recurringDesc = recurringToDelete
          ? formatRecurringDescription(recurringToDelete, tr)
          : "unknown";

        return {
          success: true,
          message: t(tr.deletedRecurring, { description: recurringDesc }),
        };
      }

      case "list": {
        const supabase = await createSupabaseServerClient();

        if (input.recurringId) {
          // Resolve short ID to full UUID
          const fullRecurringId = await resolveRecurringId(input.recurringId, _userId);
          if (!fullRecurringId) {
            return {
              success: false,
              message: t(tr.recurringNotFound, { id: input.recurringId }),
            };
          }

          // List specific recurring shift
          const { data, error } = await supabase
            .from("recurring_shifts")
            .select("*")
            .eq("id", fullRecurringId)
            .eq("user_id", _userId)
            .single();

          if (error) {
            throw new Error(`Failed to fetch recurring shift: ${error.message}`);
          }

          if (!data) {
            return {
              success: false,
              message: t(tr.recurringNotFound, { id: input.recurringId }),
            };
          }

          return {
            success: true,
            message: t(tr.foundRecurring, { description: formatRecurringDescription(data, tr) }),
            data: [formatRecurringForAI(data)],
          };
        } else {
          // List all user's recurring shifts
          const { data, error } = await supabase
            .from("recurring_shifts")
            .select("*")
            .eq("user_id", _userId)
            .order("created_at", { ascending: false });

          if (error) {
            throw new Error(`Failed to fetch recurring shifts: ${error.message}`);
          }

          return {
            success: true,
            message: t(tr.foundRecurringCount, { count: data.length }),
            data: data.map(formatRecurringForAI),
          };
        }
      }

      default:
        return {
          success: false,
          message: t(tr.unknownAction, { action: input.action }),
        };
    }
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Failed to execute recurring shift operation"
    );
  }
}

/**
 * Execute manage_recurring_exclusion tool (consolidated add/remove)
 */
async function executeManageRecurringExclusion(
  args: unknown,
  _userId: string,
  tr: ToolResultTranslations
): Promise<ToolResult> {
  const parsed = manageRecurringExclusionSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: t(tr.invalidInput, { details: parsed.error.issues.map((i: any) => i.message).join(", ") }),
    };
  }

  const input: ManageRecurringExclusionInput = parsed.data;

  try {
    // Resolve short ID to full UUID
    const fullRecurringId = await resolveRecurringId(input.recurringId, _userId);
    if (!fullRecurringId) {
      return {
        success: false,
        message: t(tr.recurringNotFound, { id: input.recurringId }),
      };
    }

    const supabase = await createSupabaseServerClient();

    // Fetch current recurring shift
    const { data: recurring, error: fetchError } = await supabase
      .from("recurring_shifts")
      .select("exclusions, selected_days, start_time, end_time")
      .eq("id", fullRecurringId)
      .eq("user_id", _userId)
      .single();

    if (fetchError || !recurring) {
      return {
        success: false,
        message: t(tr.recurringNotFound, { id: input.recurringId }),
      };
    }

    const currentExclusions = (recurring.exclusions as string[]) || [];
    let newExclusions: string[];

    if (input.action === "add") {
      // Add date to exclusions (deduplicate and sort)
      newExclusions = Array.from(new Set([...currentExclusions, input.date])).sort();
    } else {
      // Remove date from exclusions
      newExclusions = currentExclusions.filter((date) => date !== input.date);
    }

    // Update recurring shift
    const { error: updateError } = await supabase
      .from("recurring_shifts")
      .update({ exclusions: newExclusions })
      .eq("id", fullRecurringId)
      .eq("user_id", _userId);

    if (updateError) {
      throw new Error(`Failed to update recurring shift: ${updateError.message}`);
    }

    const recurringDesc = formatRecurringDescription(recurring, tr);
    const dateDesc = formatDateCompact(input.date, tr);
    // Note: These messages aren't in the translation file, keeping them simple
    const actionMessage = input.action === "add"
      ? `Excluded ${dateDesc} from recurring shift (${recurringDesc})`
      : `Removed ${dateDesc} from exclusions in recurring shift (${recurringDesc})`;

    return {
      success: true,
      message: actionMessage,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Failed to update exclusions"
    );
  }
}

/**
 * Execute get_statistics tool
 */
async function executeGetStatistics(
  args: unknown,
  userId: string,
  tr: ToolResultTranslations
): Promise<ToolResult> {
  const parsed = getStatisticsSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: t(tr.invalidInput, { details: parsed.error.issues.map((i: any) => i.message).join(", ") }),
    };
  }

  const input: GetStatisticsInput = parsed.data;

  try {
    // Get user's currency and stats data in parallel
    const [currency, statsData] = await Promise.all([
      getUserCurrency(userId),
      getStatsDataForApi(userId, {
        year: input.year,
        month: input.month,
      }),
    ]);

    // Extract requested metric
    let data: any;
    let message: string;

    switch (input.metric) {
      case "current_month":
        data = statsData.currentMonth;
        message = tr.statsCurrentMonth;
        break;
      case "last_month":
        data = statsData.lastMonth;
        message = tr.statsLastMonth;
        break;
      case "year_to_date":
        data = statsData.yearToDate;
        message = tr.statsYearToDate;
        break;
      case "last_6_months":
        data = statsData.last6Months;
        message = tr.statsLast6Months;
        break;
      case "this_week":
        data = statsData.thisWeek;
        message = tr.statsThisWeek;
        break;
      case "monthly_goal":
        data = statsData.monthlyGoal;
        message = tr.statsMonthlyGoal;
        break;
      case "supplement_breakdown":
        data = statsData.currentMonthBreakdown;
        message = tr.statsSupplementBreakdown;
        break;
      default:
        return {
          success: false,
          message: t(tr.unknownMetric, { metric: input.metric }),
        };
    }

    return {
      success: true,
      message,
      data,
      currency,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : tr.failedToFetchStatistics
    );
  }
}

/**
 * Execute manage_settings tool (consolidated view/update)
 */
async function executeManageSettings(
  args: unknown,
  userId: string,
  tr: ToolResultTranslations
): Promise<ToolResult> {
  console.log("[manage_settings] Starting execution for userId:", userId);
  console.log("[manage_settings] Args:", args);

  const parsed = manageSettingsSchema.safeParse(args);
  if (!parsed.success) {
    console.error("[manage_settings] Validation failed:", parsed.error);
    return {
      success: false,
      message: t(tr.invalidInput, { details: parsed.error.issues.map((i: any) => i.message).join(", ") }),
    };
  }

  const input: ManageSettingsInput = parsed.data;
  console.log("[manage_settings] Validation passed, action:", input.action);

  try {
    if (input.action === "update") {
      // Update settings
      if (!input.category || !input.settings) {
        return {
          success: false,
          message: tr.mustProvideCategoryAndSettings,
        };
      }

      console.log("[manage_settings] Updating settings, category:", input.category);

      // Import the update actions
      const { updateDisplaySettings, updatePaySettings, updatePreferencesSettings } = await import(
        "@/app/[locale]/(app)/settings/_actions/updateSettings"
      );

      let result: { success: boolean };

      switch (input.category) {
        case "display": {
          const displayData: { theme?: string; default_shifts_view?: string } = {};
          if (input.settings.theme) displayData.theme = input.settings.theme;
          if (input.settings.defaultShiftsView) displayData.default_shifts_view = input.settings.defaultShiftsView;

          result = await updateDisplaySettings(displayData);
          break;
        }

        case "payroll": {
          const payrollData: {
            pause_deduction_enabled?: boolean;
            pause_deduction_method?: string | null;
            pause_threshold_hours?: number | null;
            pause_deduction_minutes?: number | null;
          } = {};

          if (input.settings.pauseDeductionEnabled !== undefined) {
            payrollData.pause_deduction_enabled = input.settings.pauseDeductionEnabled;
          }
          if (input.settings.pauseDeductionMethod !== undefined) {
            payrollData.pause_deduction_method = input.settings.pauseDeductionMethod;
          }
          if (input.settings.pauseThresholdHours !== undefined) {
            payrollData.pause_threshold_hours = input.settings.pauseThresholdHours;
          }
          if (input.settings.pauseDeductionMinutes !== undefined) {
            payrollData.pause_deduction_minutes = input.settings.pauseDeductionMinutes;
          }

          result = await updatePaySettings(payrollData);
          break;
        }

        case "tax": {
          const taxData: {
            tax_deduction_enabled?: boolean;
            tax_percentage?: number | null;
            half_tax_month?: number | null;
          } = {};

          if (input.settings.taxDeductionEnabled !== undefined) {
            taxData.tax_deduction_enabled = input.settings.taxDeductionEnabled;
          }
          if (input.settings.taxPercentage !== undefined) {
            taxData.tax_percentage = input.settings.taxPercentage;
          }
          if (input.settings.halfTaxMonth !== undefined) {
            taxData.half_tax_month = input.settings.halfTaxMonth;
          }

          result = await updatePaySettings(taxData);
          break;
        }

        case "goals": {
          const goalsData: {
            monthly_goal?: number | null;
            payroll_day?: number | null;
          } = {};

          if (input.settings.monthlyGoal !== undefined) {
            goalsData.monthly_goal = input.settings.monthlyGoal;
          }
          if (input.settings.payrollDay !== undefined) {
            goalsData.payroll_day = input.settings.payrollDay;
          }

          result = await updatePaySettings(goalsData);
          break;
        }

        case "preferences": {
          const preferencesData: {
            direct_time_input?: boolean;
            full_minute_range?: boolean;
          } = {};

          if (input.settings.directTimeInput !== undefined) {
            preferencesData.direct_time_input = input.settings.directTimeInput;
          }
          if (input.settings.fullMinuteRange !== undefined) {
            preferencesData.full_minute_range = input.settings.fullMinuteRange;
          }

          result = await updatePreferencesSettings(preferencesData);
          break;
        }

        default:
          return {
            success: false,
            message: t(tr.unknownCategory, { category: input.category }),
          };
      }

      if (!result.success) {
        return {
          success: false,
          message: tr.failedToUpdateSettings,
        };
      }

      return {
        success: true,
        message: t(tr.updatedSettings, { category: input.category }),
      };
    } else {
      // View settings (default action)
      console.log("[manage_settings] Calling SettingsService...");

      // Call SettingsService directly without caching (API route context)
      const program = Effect.gen(function* () {
        const settingsService = yield* SettingsService;
        console.log("[manage_settings] Got SettingsService");
        const settings = yield* settingsService.getUserSettings(userId);
        console.log("[manage_settings] Got settings:", settings ? "exists" : "null");
        return settings;
      }).pipe(
        Effect.provide(AuthSettingsLive),
        Effect.catchAll((error) => {
          console.error("[manage_settings] Effect error:", error);
          logger.error("Failed to fetch user settings:", error);
          return Effect.succeed(null);
        }),
        Effect.scoped
      );

      const settings = await Effect.runPromise(program);
      console.log("[manage_settings] Effect.runPromise completed, settings:", settings ? "exists" : "null");

      if (!settings) {
        console.log("[manage_settings] No settings found, returning defaults");
        return {
          success: true,
          message: tr.noSettingsFound,
          data: {},
        };
      }

      console.log("[manage_settings] Formatting settings...");

      // Format settings for AI consumption
      const formattedSettings = {
        display: {
          theme: settings.theme || "system",
          defaultShiftsView: settings.default_shifts_view || "calendar",
        },
        payroll: {
          usePreset: settings.use_preset ?? true,
          currentWageLevel: settings.current_wage_level,
          customWage: settings.custom_wage,
          pauseDeductionEnabled: settings.pause_deduction_enabled ?? false,
          pauseDeductionMethod: settings.pause_deduction_method || "proportional",
          pauseThresholdHours: settings.pause_threshold_hours || 5.5,
          pauseDeductionMinutes: settings.pause_deduction_minutes || 30,
        },
        tax: {
          taxDeductionEnabled: settings.tax_deduction_enabled ?? false,
          taxPercentage: settings.tax_percentage || 0,
          halfTaxMonth: settings.half_tax_month,
        },
        goals: {
          monthlyGoal: settings.monthly_goal,
          payrollDay: settings.payroll_day,
        },
        preferences: {
          directTimeInput: settings.direct_time_input ?? false,
          fullMinuteRange: settings.full_minute_range ?? false,
        },
      };

      console.log("[manage_settings] Returning success with formatted settings");

      return {
        success: true,
        message: tr.retrievedSettings,
        data: formattedSettings,
      };
    }
  } catch (error) {
    console.error("[manage_settings] Caught error:", error);
    throw new Error(
      error instanceof Error ? error.message : tr.failedToExecuteSettingsOperation
    );
  }
}

/**
 * Execute calculate_earnings tool (hypothetical earnings calculator)
 */
async function executeCalculateEarnings(
  args: unknown,
  userId: string,
  tr: ToolResultTranslations
): Promise<ToolResult> {
  const parsed = calculateEarningsSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: t(tr.invalidInput, { details: parsed.error.issues.map((i) => i.message).join(", ") }),
    };
  }

  const input: CalculateEarningsInput = parsed.data;

  try {
    // Import payroll computation and presets
    const { computeShift, PRESET_SUPPLEMENT_RULES } = await import("@/lib/payroll");
    const { SnapshotsService } = await import("@/lib/services/snapshots");
    const { AuthSnapshotsLive } = await import("@/lib/layers/app");

    // Get user settings for break deduction
    const settingsProgram = Effect.gen(function* () {
      const settingsService = yield* SettingsService;
      const settings = yield* settingsService.getUserSettings(userId);
      return settings;
    }).pipe(
      Effect.provide(AuthSettingsLive),
      Effect.catchAll(() => Effect.succeed(null)),
      Effect.scoped
    );

    const userSettings = await Effect.runPromise(settingsProgram);

    // Get user's currency
    const currency = await getUserCurrency(userId);

    // Check if user has tax deduction enabled
    const hasTaxDeduction = userSettings?.tax_deduction_enabled && userSettings?.tax_percentage;

    // Helper function to compute earnings for a hypothetical shift
    const computeHypotheticalShift = async (
      date: string,
      startTime: string,
      endTime: string,
      label?: string
    ) => {
      // Get snapshot for the date
      const snapshotProgram = Effect.gen(function* () {
        const snapshots = yield* SnapshotsService;
        const snapshot = yield* snapshots.getSnapshotForDate(userId, date);
        return snapshot;
      }).pipe(
        Effect.provide(AuthSnapshotsLive),
        Effect.catchAll(() => Effect.succeed(null)),
        Effect.scoped
      );

      const snapshot = await Effect.runPromise(snapshotProgram);

      // Build a fake shift row for computation
      const fakeShift = {
        id: `hypothetical-${Date.now()}`,
        user_id: userId,
        shift_date: date,
        start_time: startTime,
        end_time: endTime,
      };

      // Compute the shift
      const computed = computeShift(
        fakeShift,
        {
          pause_deduction_enabled: userSettings?.pause_deduction_enabled ?? true,
          pause_deduction_method: (userSettings?.pause_deduction_method ?? "proportional") as BreakMethod,
          pause_threshold_hours: userSettings?.pause_threshold_hours ?? 5.5,
          pause_deduction_minutes: userSettings?.pause_deduction_minutes ?? 30,
        },
        PRESET_SUPPLEMENT_RULES,
        snapshot
      );

      // Get weekday name
      const weekday = getWeekdayAbbr(date, tr);

      // Calculate net pay
      const net = hasTaxDeduction
        ? calculateNetPay(computed.gross, userSettings!, date)
        : computed.gross;

      return {
        label: label || `${weekday} ${formatDateCompact(date, tr)}`,
        date,
        weekday,
        start_time: startTime,
        end_time: endTime,
        duration_hours: Number(computed.durationHours.toFixed(2)),
        paid_hours: Number(computed.paidHours.toFixed(2)),
        gross: Number(computed.gross.toFixed(2)),
        net: Number(net.toFixed(2)),
        breakdown: {
          base_pay: Number(computed.basePay.toFixed(2)),
          supplement_pay: Number(computed.supplementPay.toFixed(2)),
          break_deducted_minutes: Number((computed.breakAudit.deductedHours * 60).toFixed(0)),
        },
      };
    };

    // MODE 1: Single hypothetical shift
    if (input.hypothetical) {
      const result = await computeHypotheticalShift(
        input.hypothetical.date,
        input.hypothetical.start_time,
        input.hypothetical.end_time,
        input.hypothetical.label
      );

      return {
        success: true,
        message: t(tr.calculatedHypothetical, { label: result.label }),
        data: {
          scenarios: [result],
        },
        currency,
      };
    }

    // MODE 2: Compare multiple scenarios
    if (input.compare) {
      const scenarios = await Promise.all(
        input.compare.map((scenario) =>
          computeHypotheticalShift(
            scenario.date,
            scenario.start_time,
            scenario.end_time,
            scenario.label
          )
        )
      );

      // Find best and worst
      const sortedByGross = [...scenarios].sort((a, b) => b.gross - a.gross);
      const best = sortedByGross[0];
      const worst = sortedByGross[sortedByGross.length - 1];
      const difference = Number((best.gross - worst.gross).toFixed(2));

      // Generate comparison summary
      let summary = "";
      if (difference > 0) {
        const supplementDiff = Number(
          (best.breakdown.supplement_pay - worst.breakdown.supplement_pay).toFixed(2)
        );
        if (supplementDiff > difference * 0.5) {
          summary = `"${best.label}" earns ${difference} ${currency} more, mostly from evening/weekend supplements`;
        } else {
          summary = `"${best.label}" earns ${difference} ${currency} more`;
        }
      } else {
        summary = "Both scenarios earn the same amount";
      }

      return {
        success: true,
        message: t(tr.comparedScenarios, { count: scenarios.length }),
        data: {
          scenarios,
          comparison: {
            best_option: best.label,
            worst_option: worst.label,
            difference,
            summary,
          },
        },
        currency,
      };
    }

    // MODE 3: Hypothetical change to existing shift
    if (input.hypothetical_change) {
      // Fetch shifts with a wide date range to include future virtual shifts
      // Use 6 months back and 12 months forward to cover most scenarios
      const now = new Date();
      const sixMonthsAgo = new Date(now.getFullYear(), now.getMonth() - 6, 1);
      const twelveMonthsAhead = new Date(now.getFullYear(), now.getMonth() + 13, 0);

      const shiftsResult = await getComputedShiftsForApi(userId, {
        startDate: sixMonthsAgo.toISOString().split("T")[0],
        endDate: twelveMonthsAhead.toISOString().split("T")[0],
        limit: 2000,
      });

      const fullShiftId = resolveShortIdFromShifts(
        input.hypothetical_change.shift_id,
        shiftsResult.shifts
      );

      if (!fullShiftId) {
        return {
          success: false,
          message: t(tr.shiftNotFound, { id: input.hypothetical_change.shift_id }),
        };
      }

      const originalShift = shiftsResult.shifts.find((s) => s.id === fullShiftId);
      if (!originalShift) {
        return {
          success: false,
          message: t(tr.shiftNotFound, { id: input.hypothetical_change.shift_id }),
        };
      }

      // Calculate original earnings
      const originalResult = await computeHypotheticalShift(
        originalShift.shift_date,
        originalShift.start_time,
        originalShift.end_time,
        "Original"
      );

      // Calculate modified earnings
      const changes = input.hypothetical_change.changes;
      const modifiedResult = await computeHypotheticalShift(
        changes.date || originalShift.shift_date,
        changes.start_time || originalShift.start_time,
        changes.end_time || originalShift.end_time,
        "Modified"
      );

      const difference = Number((modifiedResult.gross - originalResult.gross).toFixed(2));
      const differenceStr =
        difference > 0 ? `+${difference}` : difference === 0 ? "0" : `${difference}`;

      return {
        success: true,
        message: t(tr.calculatedChange, { difference: differenceStr }),
        data: {
          original: originalResult,
          modified: modifiedResult,
          difference,
          difference_net: Number((modifiedResult.net - originalResult.net).toFixed(2)),
        },
        currency,
      };
    }

    // Should never reach here due to schema validation
    return {
      success: false,
      message: tr.mustSpecifyMode,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : tr.failedToCalculateEarnings
    );
  }
}
