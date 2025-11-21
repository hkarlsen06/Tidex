/**
 * Tool Executor
 *
 * Executes chat tools with validation, authentication, and retry logic
 */

import { createShifts } from "@/app/[locale]/(app)/shifts/add/actions";
import { updateShift } from "@/app/[locale]/(app)/shifts/_actions/updateShift";
import { deleteShift } from "@/app/[locale]/(app)/shifts/_actions/deleteShift";
import { getComputedShiftsForApi } from "@/data-access/shifts";
import type {
  ToolName,
  ToolResult,
  AddShiftInput,
  UpdateShiftInput,
  DeleteShiftInput,
  BulkDeleteShiftsInput,
  QueryShiftsInput,
  CalculateWagesInput,
} from "./tools";
import {
  addShiftSchema,
  updateShiftSchema,
  deleteShiftSchema,
  bulkDeleteShiftsSchema,
  queryShiftsSchema,
  calculateWagesSchema,
} from "./tools";

/**
 * Execute a tool call with retry logic
 */
const KNOWN_TOOL_NAMES: ToolName[] = [
  "add_shift",
  "update_shift",
  "delete_shift",
  "bulk_delete_shifts",
  "query_shifts",
  "calculate_wages",
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
  try {
    const normalizedToolName = normalizeToolName(toolName);

    if (!normalizedToolName) {
      return {
        success: false,
        message: `Ukjent verktøy: ${toolName}`,
      };
    }

    // Parse arguments
    const args = JSON.parse(argumentsJson);

    // Execute tool with retry (once)
    let attempt = 0;
    let lastError: Error | null = null;

    while (attempt < 2) {
      try {
        return await executeToolOnce(normalizedToolName, args, userId);
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        attempt++;

        if (attempt < 2) {
          // Wait 500ms before retry
          await new Promise((resolve) => setTimeout(resolve, 500));
        }
      }
    }

    // All attempts failed
    return {
      success: false,
      message: `Feilet etter ${attempt} forsøk: ${lastError?.message || "Ukjent feil"}`,
    };
  } catch (error) {
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
    case "add_shift":
      return await executeAddShift(args, userId);

    case "update_shift":
      return await executeUpdateShift(args, userId);

    case "delete_shift":
      return await executeDeleteShift(args, userId);

    case "bulk_delete_shifts":
      return await executeBulkDeleteShifts(args, userId);

    case "query_shifts":
      return await executeQueryShifts(args, userId);

    case "calculate_wages":
      return await executeCalculateWages(args, userId);

    default:
      return {
        success: false,
        message: `Ukjent verktøy: ${toolName}`,
      };
  }
}

/**
 * Execute add_shift tool
 */
async function executeAddShift(
  args: unknown,
  _userId: string
): Promise<ToolResult> {
  const parsed = addShiftSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i) => i.message).join(", ")}`,
    };
  }

  const input: AddShiftInput = parsed.data;

  try {
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
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke legge til skift"
    );
  }
}

/**
 * Execute update_shift tool
 */
async function executeUpdateShift(
  args: unknown,
  userId: string
): Promise<ToolResult> {
  const parsed = updateShiftSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i) => i.message).join(", ")}`,
    };
  }

  const input: UpdateShiftInput = parsed.data;

  // At least one field must be updated
  if (!input.date && !input.start && !input.end) {
    return {
      success: false,
      message: "Må oppgi minst én verdi å oppdatere (dato, start eller slutt)",
    };
  }

  try {
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
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke oppdatere skift"
    );
  }
}

/**
 * Execute delete_shift tool
 */
async function executeDeleteShift(
  args: unknown,
  _userId: string
): Promise<ToolResult> {
  const parsed = deleteShiftSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i) => i.message).join(", ")}`,
    };
  }

  const input: DeleteShiftInput = parsed.data;

  try {
    await deleteShift(input.shiftId);

    return {
      success: true,
      message: `Slettet skift ${input.shiftId}`,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke slette skift"
    );
  }
}

/**
 * Execute bulk_delete_shifts tool
 */
async function executeBulkDeleteShifts(
  args: unknown,
  _userId: string
): Promise<ToolResult> {
  const parsed = bulkDeleteShiftsSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i) => i.message).join(", ")}`,
    };
  }

  const input: BulkDeleteShiftsInput = parsed.data;

  try {
    // Delete all shifts
    await Promise.all(input.shiftIds.map((id) => deleteShift(id)));

    return {
      success: true,
      message: `Slettet ${input.shiftIds.length} ${input.shiftIds.length === 1 ? "skift" : "skift"}`,
    };
  } catch (error) {
    throw new Error(
      error instanceof Error ? error.message : "Kunne ikke slette skift"
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
 * Execute query_shifts tool
 */
async function executeQueryShifts(
  args: unknown,
  userId: string
): Promise<ToolResult> {
  const parsed = queryShiftsSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i) => i.message).join(", ")}`,
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
      limit: input.limit,
    });

    // Format shifts for AI with pre-formatted display strings
    const shiftsFormatted = result.shifts.map((shift) => ({
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
      message: `Fant ${result.shifts.length} ${result.shifts.length === 1 ? "skift" : "skift"}`,
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
 * Get date range for an ISO week number
 */
function getWeekDateRange(week: number, year: number): { startDate: string; endDate: string } {
  // ISO 8601: Week 1 is the week with the first Thursday of the year
  // Week starts on Monday
  const jan4 = new Date(Date.UTC(year, 0, 4)); // January 4th is always in week 1
  const daysSinceMonday = (jan4.getUTCDay() + 6) % 7; // 0=Mon, 1=Tue, ..., 6=Sun
  const week1Monday = new Date(jan4);
  week1Monday.setUTCDate(jan4.getUTCDate() - daysSinceMonday);

  // Calculate target week's Monday
  const targetMonday = new Date(week1Monday);
  targetMonday.setUTCDate(week1Monday.getUTCDate() + (week - 1) * 7);

  // Calculate Sunday (end of week)
  const targetSunday = new Date(targetMonday);
  targetSunday.setUTCDate(targetMonday.getUTCDate() + 6);

  // Format as YYYY-MM-DD
  const formatDate = (date: Date) => {
    const y = date.getUTCFullYear();
    const m = String(date.getUTCMonth() + 1).padStart(2, "0");
    const d = String(date.getUTCDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  };

  return {
    startDate: formatDate(targetMonday),
    endDate: formatDate(targetSunday),
  };
}

/**
 * Execute calculate_wages tool
 */
async function executeCalculateWages(
  args: unknown,
  userId: string
): Promise<ToolResult> {
  const parsed = calculateWagesSchema.safeParse(args);
  if (!parsed.success) {
    return {
      success: false,
      message: `Ugyldig input: ${parsed.error.issues.map((i) => i.message).join(", ")}`,
    };
  }

  let input: CalculateWagesInput = parsed.data;

  // Auto-correct mixed parameters by choosing the most appropriate method
  const hasShiftIds = input.shiftIds && input.shiftIds.length > 0;
  const hasDateRange = input.startDate || input.endDate;
  const hasWeek = input.week !== undefined;

  const methodCount = [hasShiftIds, hasDateRange, hasWeek].filter(Boolean).length;

  if (methodCount === 0) {
    return {
      success: false,
      message: "Må oppgi enten skift-IDer, datoperiode (startDato/sluttDato), eller ukenummer",
    };
  }

  // AUTO-FIX: If multiple methods are provided, choose the best one intelligently
  // Priority logic:
  // 1. shiftIds (most specific - exact shift selection)
  // 2. dateRange (explicit dates from user query - "today", "this month", etc.)
  // 3. week (only if no dates provided - "this week", "last week")
  //
  // CRITICAL: Always prefer dateRange over week when both are present
  // The AI correctly extracts explicit dates from questions like "today" or "this month"
  // Week numbers are often hallucinated when the AI shouldn't send them
  if (methodCount > 1) {
    if (hasShiftIds) {
      // Use shiftIds only (most specific - exact shift selection)
      input = {
        shiftIds: input.shiftIds,
      };
    } else if (hasDateRange) {
      // Always prefer dateRange when present (explicit dates are more specific than weeks)
      input = {
        startDate: input.startDate,
        endDate: input.endDate,
      };
    } else if (hasWeek) {
      // Only use week if no dates provided
      input = {
        week: input.week,
        year: input.year,
      };
    }
  }

  // Recalculate flags after auto-fix to reflect the actual method being used
  const finalHasShiftIds = input.shiftIds && input.shiftIds.length > 0;
  const finalHasDateRange = input.startDate || input.endDate;
  const finalHasWeek = input.week !== undefined;

  // If week is provided, convert to date range
  let effectiveStartDate = input.startDate;
  let effectiveEndDate = input.endDate;
  let weekDisplay: string | null = null;

  if (finalHasWeek) {
    const year = input.year || new Date().getFullYear();
    const weekRange = getWeekDateRange(input.week!, year);
    effectiveStartDate = weekRange.startDate;
    effectiveEndDate = weekRange.endDate;
    weekDisplay = `uke ${input.week}, ${year}`;
  }

  try {
    let shifts;
    let settings;

    if (finalHasShiftIds) {
      // Fetch all shifts and filter by IDs
      const result = await getComputedShiftsForApi(userId, { limit: 1000 });
      shifts = result.shifts.filter((s) => input.shiftIds!.includes(s.id));
      settings = result.settings;

      if (shifts.length === 0) {
        return {
          success: false,
          message: "Fant ingen skift med de oppgitte IDene",
        };
      }

      if (shifts.length < input.shiftIds!.length) {
        return {
          success: false,
          message: `Fant bare ${shifts.length} av ${input.shiftIds!.length} skift`,
        };
      }
    } else {
      // Fetch shifts by date range (or week converted to date range)
      const result = await getComputedShiftsForApi(userId, {
        startDate: effectiveStartDate,
        endDate: effectiveEndDate,
        limit: 1000,
      });

      shifts = result.shifts;
      settings = result.settings;

      if (shifts.length === 0) {
        const periodDesc = weekDisplay || (effectiveStartDate && effectiveEndDate
          ? `${formatDateForDisplay(effectiveStartDate)} til ${formatDateForDisplay(effectiveEndDate)}`
          : "perioden");

        return {
          success: true,
          message: `Ingen skift funnet i ${periodDesc}`,
          data: {
            totalShifts: 0,
            totalHours: "0.00",
            totalGross: "0.00 kr",
            totalNet: "0.00 kr",
            taxDeducted: "0.00 kr",
          },
        };
      }
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
    let periodDisplay: string | null = null;
    if (finalHasWeek) {
      periodDisplay = weekDisplay;
    } else if (finalHasDateRange) {
      // Handle single date vs date range
      if (input.startDate && input.endDate && input.startDate === input.endDate) {
        // Single date
        periodDisplay = formatDateForDisplay(input.startDate);
      } else if (input.startDate && input.endDate) {
        // Date range
        periodDisplay = `${formatDateForDisplay(input.startDate)} til ${formatDateForDisplay(input.endDate)}`;
      } else if (input.startDate) {
        periodDisplay = `fra ${formatDateForDisplay(input.startDate)}`;
      } else if (input.endDate) {
        periodDisplay = `til ${formatDateForDisplay(input.endDate)}`;
      } else {
        periodDisplay = "ukjent periode";
      }
    }

    return {
      success: true,
      message: finalHasShiftIds
        ? `Beregnet lønn for ${shifts.length} ${shifts.length === 1 ? "skift" : "skift"}`
        : periodDisplay
          ? `Beregnet lønn for ${periodDisplay}`
          : `Beregnet lønn for ${shifts.length} skift`,
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
