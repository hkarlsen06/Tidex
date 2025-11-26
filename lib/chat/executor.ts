/**
 * Tool Executor
 *
 * Executes chat tools with validation, authentication, and retry logic
 */

import { createShifts } from "@/app/[locale]/(app)/shifts/add/actions";
import { updateShift } from "@/app/[locale]/(app)/shifts/_actions/updateShift";
import { deleteShift } from "@/app/[locale]/(app)/shifts/_actions/deleteShift";
import { getComputedShiftsForApi } from "@/data-access/shifts";
import { draftSeriesShift } from "@/app/[locale]/(app)/shifts/add/_actions/draftSeriesShift";
import { createSeriesShift } from "@/app/[locale]/(app)/shifts/add/_actions/createSeriesShift";
import { updateSeriesShift } from "@/app/[locale]/(app)/shifts/_actions/updateSeriesShift";
import { deleteSeriesShift } from "@/app/[locale]/(app)/shifts/_actions/deleteSeriesShift";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { EndCondition } from "@/lib/series/types";
import type {
  ToolName,
  ToolResult,
  ManageShiftInput,
  QueryShiftsInput,
  CalculateWagesInput,
  DraftSeriesShiftInput,
  ConfirmSeriesShiftInput,
  ManageSeriesShiftInput,
  ManageSeriesExclusionInput,
  GetStatisticsInput,
  ManageSettingsInput,
} from "./tools";
import {
  manageShiftSchema,
  queryShiftsSchema,
  calculateWagesSchema,
  draftSeriesShiftSchema,
  confirmSeriesShiftSchema,
  manageSeriesShiftSchema,
  manageSeriesExclusionSchema,
  getStatisticsSchema,
  manageSettingsSchema,
} from "./tools";
import { getStatsDataForApi } from "@/data-access/stats";
import { SettingsService } from "@/lib/services/settings";
import { AuthSettingsLive } from "@/lib/layers/app";
import { Effect } from "effect";
import { logger } from "@/lib/logger";

/**
 * Execute a tool call with retry logic
 */
const KNOWN_TOOL_NAMES: ToolName[] = [
  "manage_shift",
  "query_shifts",
  "calculate_wages",
  "draft_series_shift",
  "confirm_series_shift",
  "manage_series_shift",
  "manage_series_exclusion",
  "get_statistics",
  "manage_settings",
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
  userId: string
): Promise<ToolResult> {
  console.log("[executeTool] Called with tool:", toolName, "userId:", userId);
  console.log("[executeTool] Arguments JSON:", argumentsJson);

  try {
    const normalizedToolName = normalizeToolName(toolName);

    if (!normalizedToolName) {
      console.error("[executeTool] Unknown tool:", toolName);
      return {
        success: false,
        message: `Ukjent verktøy: ${toolName}`,
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
        const result = await executeToolOnce(normalizedToolName, args, userId);
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
      message: `Feilet etter ${attempt} forsøk: ${lastError?.message || "Ukjent feil"}`,
    };
  } catch (error) {
    console.error("[executeTool] Error parsing arguments:", error);
    return {
      success: false,
      message: `Kunne ikke parse argumenter: ${error instanceof Error ? error.message : "Ukjent feil"}`,
    };
  }
}

/**
 * Execute tool once (no retry)
 */
async function executeToolOnce(
  toolName: ToolName,
  args: unknown,
  userId: string
): Promise<ToolResult> {
  switch (toolName) {
    case "manage_shift":
      return await executeManageShift(args, userId);

    case "query_shifts":
      return await executeQueryShifts(args, userId);

    case "calculate_wages":
      return await executeCalculateWages(args, userId);

    case "draft_series_shift":
      return await executeDraftSeriesShift(args, userId);

    case "confirm_series_shift":
      return await executeConfirmSeriesShift(args, userId);

    case "manage_series_shift":
      return await executeManageSeriesShift(args, userId);

    case "manage_series_exclusion":
      return await executeManageSeriesExclusion(args, userId);

    case "get_statistics":
      return await executeGetStatistics(args, userId);

    case "manage_settings":
      return await executeManageSettings(args, userId);

    default:
      return {
        success: false,
        message: `Ukjent verktøy: ${toolName}`,
      };
  }
}

/**
 * Execute manage_shift tool (consolidated CRUD)
 */
async function executeManageShift(
  args: unknown,
  userId: string
): Promise<ToolResult> {
  const parsed = manageShiftSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i) => i.message).join(", ")}`,
    };
  }

  const input: ManageShiftInput = parsed.data;

  try {
    switch (input.action) {
      case "create": {
        if (!input.dates || !input.start || !input.end) {
          return {
            success: false,
            message: "Mangler påkrevde felter for oppretting: dates, start, end",
          };
        }

        const result = await createShifts({
          dates: input.dates,
          start: input.start,
          end: input.end,
        });

        return {
          success: true,
          message: `Lagt til ${result.inserted} ${result.inserted === 1 ? "skift" : "skift"} for ${input.dates.join(", ")}`,
          data: result,
        };
      }

      case "update": {
        if (!input.shiftId) {
          return {
            success: false,
            message: "Mangler shiftId for oppdatering",
          };
        }

        // At least one field must be updated
        if (!input.date && !input.start && !input.end) {
          return {
            success: false,
            message: "Må oppgi minst én verdi å oppdatere (dato, start eller slutt)",
          };
        }

        // Fetch current shift to get existing values
        const shifts = await getComputedShiftsForApi(userId, { limit: 1000 });
        const shift = shifts.shifts.find((s) => s.id === input.shiftId);

        if (!shift) {
          return {
            success: false,
            message: `Fant ikke skift med ID ${input.shiftId}`,
          };
        }

        await updateShift({
          id: input.shiftId,
          shift_date: input.date || shift.shift_date,
          start: input.start || shift.start_time,
          end: input.end || shift.end_time,
        });

        return {
          success: true,
          message: `Oppdaterte skift ${input.shiftId}`,
        };
      }

      case "delete": {
        // Support both single and bulk delete
        if (input.shiftIds && input.shiftIds.length > 0) {
          // Bulk delete - fetch shifts first for display info
          const shifts = await getComputedShiftsForApi(userId, { limit: 1000 });
          const shiftsToDelete = shifts.shifts.filter((s) => input.shiftIds!.includes(s.id));

          await Promise.all(input.shiftIds.map((id) => deleteShift(id)));

          // Format deleted shifts info
          const deletedInfo = shiftsToDelete.map((s) =>
            `${formatDateForDisplay(s.shift_date)} ${s.start_time}-${s.end_time}`
          ).join(", ");

          return {
            success: true,
            message: `Slettet ${input.shiftIds.length} ${input.shiftIds.length === 1 ? "skift" : "skift"}${deletedInfo ? `: ${deletedInfo}` : ""}`,
          };
        } else if (input.shiftId) {
          // Single delete - fetch shift first for display info
          const shifts = await getComputedShiftsForApi(userId, { limit: 1000 });
          const shift = shifts.shifts.find((s) => s.id === input.shiftId);

          await deleteShift(input.shiftId);

          // Format message with date and times if shift was found
          const shiftInfo = shift
            ? `${formatDateForDisplay(shift.shift_date)} ${shift.start_time}-${shift.end_time}`
            : input.shiftId;

          return {
            success: true,
            message: `Slettet skift: ${shiftInfo}`,
          };
        } else {
          return {
            success: false,
            message: "Mangler shiftId eller shiftIds for sletting",
          };
        }
      }

      default:
        return {
          success: false,
          message: `Ukjent handling: ${input.action}`,
        };
    }
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke utføre skift-operasjon"
    );
  }
}

/**
 * Format date from YYYY-MM-DD to DD-MM-YYYY with weekday (Norwegian)
 */
function formatDateForDisplay(isoDate: string): string {
  const date = new Date(isoDate + "T12:00:00"); // Noon to avoid timezone issues
  const weekdays = ["søndag", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag"];
  const weekday = weekdays[date.getDay()];
  const day = String(date.getDate()).padStart(2, "0");
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const year = date.getFullYear();
  return `${weekday} ${day}-${month}-${year}`;
}

/**
 * Execute query_shifts tool (enhanced with filters)
 */
async function executeQueryShifts(
  args: unknown,
  userId: string
): Promise<ToolResult> {
  const parsed = queryShiftsSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i: any) => i.message).join(", ")}`,
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

    // Format shifts for AI with pre-formatted display strings
    const shiftsFormatted = limitedShifts.map((shift) => ({
      id: shift.id,
      displayDate: formatDateForDisplay(shift.shift_date),
      date: shift.shift_date, // Keep ISO format for reference
      start: shift.start_time,
      end: shift.end_time,
      hours: shift.computed.paidHours.toFixed(2),
      gross: `${shift.computed.gross.toFixed(2)} kr`,
    }));

    return {
      success: true,
      message: `Fant ${shiftsFormatted.length} ${shiftsFormatted.length === 1 ? "skift" : "skift"}`,
      data: shiftsFormatted,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke hente skift"
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
  userId: string
): Promise<ToolResult> {
  const parsed = calculateWagesSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i: any) => i.message).join(", ")}`,
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

    // Handle case where no shifts found
    if (shifts.length === 0) {
      const periodDesc = input.startDate === input.endDate
        ? formatDateForDisplay(input.startDate)
        : `${formatDateForDisplay(input.startDate)} til ${formatDateForDisplay(input.endDate)}`;

      return {
        success: true,
        message: `Ingen skift funnet for ${periodDesc}`,
        data: {
          totalShifts: 0,
          totalHours: "0.00",
          totalGross: "0.00 kr",
          totalNet: "0.00 kr",
          taxDeducted: "0.00 kr",
          period: periodDesc,
        },
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

    // Format period display
    const periodDisplay = input.startDate === input.endDate
      ? formatDateForDisplay(input.startDate)
      : `${formatDateForDisplay(input.startDate)} til ${formatDateForDisplay(input.endDate)}`;

    return {
      success: true,
      message: `Beregnet lønn for ${periodDisplay}`,
      data: {
        totalShifts: shifts.length,
        totalHours: totalHours.toFixed(2),
        totalGross: `${totalGross.toFixed(2)} kr`,
        totalNet: `${totalNet.toFixed(2)} kr`,
        taxDeducted: `${totalTaxDeducted.toFixed(2)} kr`,
        period: periodDisplay,
      },
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke beregne lønn"
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
 * Execute draft_series_shift tool (Step 1 of 2)
 */
async function executeDraftSeriesShift(
  args: unknown,
  _userId: string
): Promise<ToolResult> {
  const parsed = draftSeriesShiftSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i) => i.message).join(", ")}`,
    };
  }

  const input: DraftSeriesShiftInput = parsed.data;

  // Convert weekdays array to selected_days object (supports multiple weekdays)
  const selectedDays = weekdaysArrayToSelectedDays(input.weekdays);
  const repeatIntervalWeeks = frequencyToIntervalWeeks(input.frequency);
  const endCondition = convertEndCondition(input.endType, input.endValue);

  // Format weekdays for display in message
  const weekdayNames = ["søndag", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag"];
  const selectedWeekdayNames = input.weekdays.map(w => weekdayNames[w.day]).join(", ");

  try {
    const result = await draftSeriesShift({
      selected_days: selectedDays,
      start_time: input.start,
      end_time: input.end,
      repeat_interval_weeks: repeatIntervalWeeks,
      end_condition: endCondition,
      exclusions: [],
    });

    const weekdaysInfo = input.weekdays.length > 1
      ? ` på ${selectedWeekdayNames}`
      : ` på ${selectedWeekdayNames}`;

    if (result.conflictCount === 0) {
      return {
        success: true,
        message: `Validert serie${weekdaysInfo}. Vil opprette ${result.projectedShiftCount} vakter. Ingen konflikter funnet.`,
        data: result,
      };
    }

    return {
      success: true,
      message: `Validert serie${weekdaysInfo}. Vil opprette ${result.projectedShiftCount} vakter, men fant ${result.conflictCount} ${result.conflictCount === 1 ? "konflikt" : "konflikter"} med eksisterende vakter.`,
      data: result,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke validere serie"
    );
  }
}

/**
 * Execute confirm_series_shift tool (Step 2 of 2)
 */
async function executeConfirmSeriesShift(
  args: unknown,
  _userId: string
): Promise<ToolResult> {
  const parsed = confirmSeriesShiftSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i) => i.message).join(", ")}`,
    };
  }

  const input: ConfirmSeriesShiftInput = parsed.data;

  // Convert weekdays array to selected_days object (supports multiple weekdays)
  const selectedDays = weekdaysArrayToSelectedDays(input.weekdays);
  const repeatIntervalWeeks = frequencyToIntervalWeeks(input.frequency);
  const endCondition = convertEndCondition(input.endType, input.endValue);

  // Map new conflict resolution names to old ones
  const conflictResolution = input.conflictResolution === "skip_conflicts" ? "exclude_conflicts" : "keep_existing";

  // Format weekdays for display in message
  const weekdayNames = ["søndag", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag"];
  const selectedWeekdayNames = input.weekdays.map(w => weekdayNames[w.day]).join(", ");

  try {
    const result = await createSeriesShift(
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

    const weekdaysInfo = input.weekdays.length > 1
      ? ` for ${selectedWeekdayNames}`
      : ` for ${selectedWeekdayNames}`;

    return {
      success: true,
      message: `Serie opprettet${weekdaysInfo}. ${input.conflictResolution === "skip_conflicts" ? "Ev. konflikter ble ekskludert fra serien." : "Eksisterende vakter ble beholdt."}`,
      data: result,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke opprette serie"
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
 * Format series data for AI consumption
 */
function formatSeriesForAI(series: any): any {
  const selectedDays = series.selected_days || {};

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

  const { endType, endValue } = formatEndConditionForAI(series.end_condition as EndCondition);

  return {
    seriesId: series.id,
    weekdays, // Array of {day, anchorDate} objects (supports multiple weekdays)
    start: parseTime(series.start_time),
    end: parseTime(series.end_time),
    frequency: intervalWeeksToFrequency(series.repeat_interval_weeks),
    endType,
    endValue,
    exclusions: series.exclusions || [],
    createdAt: series.created_at,
  };
}

/**
 * Execute manage_series_shift tool (consolidated update/delete/list)
 */
async function executeManageSeriesShift(
  args: unknown,
  _userId: string
): Promise<ToolResult> {
  const parsed = manageSeriesShiftSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i) => i.message).join(", ")}`,
    };
  }

  const input: ManageSeriesShiftInput = parsed.data;

  try {
    switch (input.action) {
      case "update": {
        if (!input.seriesId) {
          return {
            success: false,
            message: "Mangler seriesId for oppdatering",
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
            message: "Må oppgi minst én verdi å oppdatere",
          };
        }

        const supabase = await createSupabaseServerClient();

        // Fetch current series to merge with updates
        const { data: currentSeries, error: fetchError } = await supabase
          .from("series_shifts")
          .select("*")
          .eq("id", input.seriesId)
          .eq("user_id", _userId)
          .single();

        if (fetchError || !currentSeries) {
          return {
            success: false,
            message: `Fant ikke serie med ID ${input.seriesId}`,
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
          selectedDays = currentSeries.selected_days as Record<'0' | '1' | '2' | '3' | '4' | '5' | '6', string>;
        }

        // Build end_condition - either from new input or keep existing
        let endCondition: EndCondition;
        if (input.endType !== undefined) {
          endCondition = convertEndCondition(input.endType, input.endValue);
        } else {
          endCondition = currentSeries.end_condition as EndCondition;
        }

        // Build repeat_interval_weeks
        const repeatIntervalWeeks = input.frequency !== undefined
          ? frequencyToIntervalWeeks(input.frequency)
          : (currentSeries.repeat_interval_weeks as 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8);

        await updateSeriesShift({
          id: input.seriesId,
          selected_days: selectedDays,
          start_time: input.start ?? parseTime(currentSeries.start_time),
          end_time: input.end ?? parseTime(currentSeries.end_time),
          repeat_interval_weeks: repeatIntervalWeeks,
          end_condition: endCondition,
          exclusions: currentSeries.exclusions || [],
        });

        return {
          success: true,
          message: `Oppdaterte serie ${input.seriesId}`,
        };
      }

      case "delete": {
        if (!input.seriesId) {
          return {
            success: false,
            message: "Mangler seriesId for sletting",
          };
        }

        await deleteSeriesShift(input.seriesId);

        return {
          success: true,
          message: `Slettet serie ${input.seriesId}`,
        };
      }

      case "list": {
        const supabase = await createSupabaseServerClient();

        if (input.seriesId) {
          // List specific series
          const { data, error } = await supabase
            .from("series_shifts")
            .select("*")
            .eq("id", input.seriesId)
            .eq("user_id", _userId)
            .single();

          if (error) {
            throw new Error(`Kunne ikke hente serie: ${error.message}`);
          }

          if (!data) {
            return {
              success: false,
              message: `Fant ikke serie med ID ${input.seriesId}`,
            };
          }

          return {
            success: true,
            message: `Fant serie ${input.seriesId}`,
            data: [formatSeriesForAI(data)],
          };
        } else {
          // List all user's series shifts
          const { data, error } = await supabase
            .from("series_shifts")
            .select("*")
            .eq("user_id", _userId)
            .order("created_at", { ascending: false });

          if (error) {
            throw new Error(`Kunne ikke hente serier: ${error.message}`);
          }

          return {
            success: true,
            message: `Fant ${data.length} ${data.length === 1 ? "serie" : "serier"}`,
            data: data.map(formatSeriesForAI),
          };
        }
      }

      default:
        return {
          success: false,
          message: `Ukjent handling: ${input.action}`,
        };
    }
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke utføre serie-operasjon"
    );
  }
}

/**
 * Execute manage_series_exclusion tool (consolidated add/remove)
 */
async function executeManageSeriesExclusion(
  args: unknown,
  _userId: string
): Promise<ToolResult> {
  const parsed = manageSeriesExclusionSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i: any) => i.message).join(", ")}`,
    };
  }

  const input: ManageSeriesExclusionInput = parsed.data;

  try {
    const supabase = await createSupabaseServerClient();

    // Fetch current series
    const { data: series, error: fetchError } = await supabase
      .from("series_shifts")
      .select("exclusions")
      .eq("id", input.seriesId)
      .eq("user_id", _userId)
      .single();

    if (fetchError || !series) {
      return {
        success: false,
        message: `Fant ikke serie med ID ${input.seriesId}`,
      };
    }

    const currentExclusions = (series.exclusions as string[]) || [];
    let newExclusions: string[];

    if (input.action === "add") {
      // Add date to exclusions (deduplicate and sort)
      newExclusions = Array.from(new Set([...currentExclusions, input.date])).sort();
    } else {
      // Remove date from exclusions
      newExclusions = currentExclusions.filter((date) => date !== input.date);
    }

    // Update series
    const { error: updateError } = await supabase
      .from("series_shifts")
      .update({ exclusions: newExclusions })
      .eq("id", input.seriesId)
      .eq("user_id", _userId);

    if (updateError) {
      throw new Error(`Kunne ikke oppdatere serie: ${updateError.message}`);
    }

    const actionMessage = input.action === "add"
      ? `Ekskluderte ${input.date} fra serie ${input.seriesId}`
      : `Fjernet ${input.date} fra ekskluderinger i serie ${input.seriesId}`;

    return {
      success: true,
      message: actionMessage,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke oppdatere ekskluderinger"
    );
  }
}

/**
 * Execute get_statistics tool
 */
async function executeGetStatistics(
  args: unknown,
  userId: string
): Promise<ToolResult> {
  const parsed = getStatisticsSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i: any) => i.message).join(", ")}`,
    };
  }

  const input: GetStatisticsInput = parsed.data;

  try {
    const statsData = await getStatsDataForApi(userId, {
      year: input.year,
      month: input.month,
    });

    // Extract requested metric
    let data: any;
    let message: string;

    switch (input.metric) {
      case "current_month":
        data = statsData.currentMonth;
        message = `Statistikk for inneværende måned`;
        break;
      case "last_month":
        data = statsData.lastMonth;
        message = `Statistikk for forrige måned`;
        break;
      case "year_to_date":
        data = statsData.yearToDate;
        message = `Statistikk år til dato`;
        break;
      case "last_6_months":
        data = statsData.last6Months;
        message = `Statistikk siste 6 måneder`;
        break;
      case "this_week":
        data = statsData.thisWeek;
        message = `Statistikk denne uken`;
        break;
      case "by_day_of_week":
        data = statsData.byDayOfWeek;
        message = `Statistikk per ukedag`;
        break;
      case "monthly_goal":
        data = statsData.monthlyGoal;
        message = `Månedsmål status`;
        break;
      case "supplement_breakdown":
        data = statsData.currentMonthBreakdown;
        message = `Tilleggsfordeling for inneværende måned`;
        break;
      default:
        return {
          success: false,
          message: `Ukjent statistikk-metrikk: ${input.metric}`,
        };
    }

    return {
      success: true,
      message,
      data,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke hente statistikk"
    );
  }
}

/**
 * Execute manage_settings tool (consolidated view/update)
 */
async function executeManageSettings(
  args: unknown,
  userId: string
): Promise<ToolResult> {
  console.log("[manage_settings] Starting execution for userId:", userId);
  console.log("[manage_settings] Args:", args);

  const parsed = manageSettingsSchema.safeParse(args);
  if (!parsed.success) {
    console.error("[manage_settings] Validation failed:", parsed.error);
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i: any) => i.message).join(", ")}`,
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
          message: "Må oppgi både 'category' og 'settings' for å oppdatere",
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
            message: `Ukjent kategori: ${input.category}`,
          };
      }

      if (!result.success) {
        return {
          success: false,
          message: "Kunne ikke oppdatere innstillinger",
        };
      }

      return {
        success: true,
        message: `Oppdaterte ${input.category}-innstillinger`,
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
          message: "Ingen innstillinger funnet (bruker standardverdier)",
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
        message: "Hentet brukerinnstillinger",
        data: formattedSettings,
      };
    }
  } catch (error) {
    console.error("[manage_settings] Caught error:", error);
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke utføre innstillingsoperasjon"
    );
  }
}
