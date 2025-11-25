/**
 * Wagey Chat Tools
 *
 * Tool definitions for AI agent to manage shifts.
 * Uses Claude format with input_examples for improved tool use accuracy.
 */

import { z } from "zod";
import type { Tool } from "@/lib/services/claude";

// =============================================================================
// ZOD SCHEMAS (for validation in executor)
// =============================================================================

/**
 * Manage Shift Tool Schema
 */
export const manageShiftSchema = z.object({
  action: z.enum(["create", "update", "delete"]),
  // Create action
  dates: z.array(z.string().regex(/^\d{4}-\d{2}-\d{2}$/)).min(1).optional(),
  start: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  end: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  // Update/delete action
  shiftId: z.string().uuid().optional(),
  shiftIds: z.array(z.string().uuid()).min(1).optional(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

export type ManageShiftInput = z.infer<typeof manageShiftSchema>;

/**
 * Query Shifts Tool Schema
 */
export const queryShiftsSchema = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  limit: z.number().int().min(1).max(100).optional().default(30),
  minTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  maxTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  weekdays: z.array(z.number().int().min(0).max(6)).optional(),
  sortBy: z.enum(["date", "earnings", "hours"]).optional().default("date"),
});

export type QueryShiftsInput = z.infer<typeof queryShiftsSchema>;

/**
 * Calculate Wages Tool Schema
 */
export const calculateWagesSchema = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});

export type CalculateWagesInput = z.infer<typeof calculateWagesSchema>;

/**
 * Draft Series Shift Tool Schema (Step 1 of 2)
 */
export const draftSeriesShiftSchema = z.object({
  weekday: z.number().int().min(0).max(6),
  anchorDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  start: z.string().regex(/^\d{2}:\d{2}$/),
  end: z.string().regex(/^\d{2}:\d{2}$/),
  frequency: z.enum(["weekly", "biweekly", "every_3_weeks", "every_4_weeks"]),
  endType: z.enum(["never", "after_months", "after_years", "on_date"]),
  endValue: z.union([z.number().int().min(1), z.string().regex(/^\d{4}-\d{2}-\d{2}$/)]).optional(),
});

export type DraftSeriesShiftInput = z.infer<typeof draftSeriesShiftSchema>;

/**
 * Confirm Series Shift Tool Schema (Step 2 of 2)
 */
export const confirmSeriesShiftSchema = z.object({
  weekday: z.number().int().min(0).max(6),
  anchorDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  start: z.string().regex(/^\d{2}:\d{2}$/),
  end: z.string().regex(/^\d{2}:\d{2}$/),
  frequency: z.enum(["weekly", "biweekly", "every_3_weeks", "every_4_weeks"]),
  endType: z.enum(["never", "after_months", "after_years", "on_date"]),
  endValue: z.union([z.number().int().min(1), z.string().regex(/^\d{4}-\d{2}-\d{2}$/)]).optional(),
  conflictResolution: z.enum(["keep_both", "skip_conflicts"]),
});

export type ConfirmSeriesShiftInput = z.infer<typeof confirmSeriesShiftSchema>;

/**
 * Manage Series Shift Tool Schema
 */
export const manageSeriesShiftSchema = z.object({
  action: z.enum(["list", "update", "delete"]),
  seriesId: z.string().uuid().optional(),
  // Update fields
  weekday: z.number().int().min(0).max(6).optional(),
  anchorDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  start: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  end: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  frequency: z.enum(["weekly", "biweekly", "every_3_weeks", "every_4_weeks"]).optional(),
  endType: z.enum(["never", "after_months", "after_years", "on_date"]).optional(),
  endValue: z.union([z.number().int().min(1), z.string().regex(/^\d{4}-\d{2}-\d{2}$/)]).optional(),
});

export type ManageSeriesShiftInput = z.infer<typeof manageSeriesShiftSchema>;

/**
 * Manage Series Exclusion Tool Schema
 */
export const manageSeriesExclusionSchema = z.object({
  seriesId: z.string().uuid(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  action: z.enum(["add", "remove"]),
});

export type ManageSeriesExclusionInput = z.infer<typeof manageSeriesExclusionSchema>;

/**
 * Get Statistics Tool Schema
 */
export const getStatisticsSchema = z.object({
  metric: z.enum([
    "current_month",
    "last_month",
    "year_to_date",
    "last_6_months",
    "this_week",
    "by_day_of_week",
    "monthly_goal",
    "supplement_breakdown",
  ]),
  year: z.number().int().min(2020).max(2100).optional(),
  month: z.number().int().min(1).max(12).optional(),
});

export type GetStatisticsInput = z.infer<typeof getStatisticsSchema>;

/**
 * Manage Settings Tool Schema
 */
export const manageSettingsSchema = z.object({
  action: z.enum(["view", "update"]).optional().default("view"),
  category: z.enum(["display", "payroll", "tax", "goals", "preferences"]).optional(),
  settings: z.record(z.string(), z.any()).optional(),
});

export type ManageSettingsInput = z.infer<typeof manageSettingsSchema>;

// =============================================================================
// TOOL DEFINITIONS (Claude format with input_examples)
// =============================================================================

export const tools: Tool[] = [
  // ---------------------------------------------------------------------------
  // SHIFT MANAGEMENT
  // ---------------------------------------------------------------------------
  {
    name: "manage_shift",
    description: `Create, update, or delete shifts.

For CREATE: provide action="create", dates (array), start, end
For UPDATE: provide action="update", shiftId, and fields to change (start, end, date)
For DELETE: provide action="delete" and either shiftId (single) or shiftIds (bulk)

IMPORTANT: Always query_shifts first to get shift IDs before update/delete.`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["create", "update", "delete"],
          description: "The operation to perform",
        },
        dates: {
          type: "array",
          items: { type: "string" },
          description: "Dates for new shifts (YYYY-MM-DD format). Only for create.",
        },
        start: {
          type: "string",
          description: "Start time (HH:mm format, 24-hour)",
        },
        end: {
          type: "string",
          description: "End time (HH:mm format, 24-hour)",
        },
        shiftId: {
          type: "string",
          description: "Single shift ID for update or delete",
        },
        shiftIds: {
          type: "array",
          items: { type: "string" },
          description: "Multiple shift IDs for bulk delete",
        },
        date: {
          type: "string",
          description: "New date when updating a shift (YYYY-MM-DD)",
        },
      },
      required: ["action"],
    },
    input_examples: [
      // Create a shift on January 15th from 9am to 5pm
      {
        action: "create",
        dates: ["2025-01-15"],
        start: "09:00",
        end: "17:00",
      },
      // Create shifts on multiple dates
      {
        action: "create",
        dates: ["2025-01-15", "2025-01-16", "2025-01-17"],
        start: "08:00",
        end: "16:00",
      },
      // Update a shift's times
      {
        action: "update",
        shiftId: "abc123-def456-ghi789",
        start: "10:00",
        end: "18:00",
      },
      // Delete a single shift
      {
        action: "delete",
        shiftId: "abc123-def456-ghi789",
      },
      // Bulk delete multiple shifts
      {
        action: "delete",
        shiftIds: ["id1", "id2", "id3"],
      },
    ],
  },

  {
    name: "query_shifts",
    description: `Get shifts with optional filters. Returns shift IDs needed for update/delete operations.

Without parameters: returns shifts for current week.
With date range: returns shifts in that period.
Filters can narrow results by time of day or weekday.`,
    input_schema: {
      type: "object",
      properties: {
        startDate: {
          type: "string",
          description: "Start of date range (YYYY-MM-DD)",
        },
        endDate: {
          type: "string",
          description: "End of date range (YYYY-MM-DD)",
        },
        limit: {
          type: "integer",
          description: "Max shifts to return (default 30, max 100)",
        },
        minTime: {
          type: "string",
          description: "Only shifts starting at or after this time (HH:mm)",
        },
        maxTime: {
          type: "string",
          description: "Only shifts starting at or before this time (HH:mm)",
        },
        weekdays: {
          type: "array",
          items: { type: "integer" },
          description: "Filter by weekday: 0=Sunday, 1=Monday, ..., 6=Saturday",
        },
        sortBy: {
          type: "string",
          enum: ["date", "earnings", "hours"],
          description: "Sort order (default: date)",
        },
      },
    },
    input_examples: [
      // Get this week's shifts (no parameters needed)
      {},
      // Get shifts for January 2025
      {
        startDate: "2025-01-01",
        endDate: "2025-01-31",
      },
      // Get evening shifts (after 5pm)
      {
        startDate: "2025-01-01",
        endDate: "2025-01-31",
        minTime: "17:00",
      },
      // Get weekend shifts only
      {
        startDate: "2025-01-01",
        endDate: "2025-01-31",
        weekdays: [0, 6],
      },
      // Get top 10 highest earning shifts
      {
        startDate: "2025-01-01",
        endDate: "2025-12-31",
        limit: 10,
        sortBy: "earnings",
      },
    ],
  },

  {
    name: "calculate_wages",
    description: `Calculate total wages for a date range. Returns gross pay, net pay, hours worked, and tax deducted.

Both startDate and endDate are required.`,
    input_schema: {
      type: "object",
      properties: {
        startDate: {
          type: "string",
          description: "Start date (YYYY-MM-DD)",
        },
        endDate: {
          type: "string",
          description: "End date (YYYY-MM-DD)",
        },
      },
      required: ["startDate", "endDate"],
    },
    input_examples: [
      // Calculate wages for January 2025
      {
        startDate: "2025-01-01",
        endDate: "2025-01-31",
      },
      // Calculate wages for a single day
      {
        startDate: "2025-01-15",
        endDate: "2025-01-15",
      },
    ],
  },

  // ---------------------------------------------------------------------------
  // RECURRING SERIES (2-step: draft then confirm)
  // ---------------------------------------------------------------------------
  {
    name: "draft_series_shift",
    description: `Step 1 of 2: Preview a recurring shift pattern WITHOUT creating it.

This validates the pattern and checks for conflicts with existing shifts.
After reviewing conflicts, use confirm_series_shift to actually create the series.

Weekday numbers: 0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday
The anchorDate must fall on the specified weekday.`,
    input_schema: {
      type: "object",
      properties: {
        weekday: {
          type: "integer",
          description: "Day of week: 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat",
        },
        anchorDate: {
          type: "string",
          description: "First occurrence date (YYYY-MM-DD). Must be the correct weekday.",
        },
        start: {
          type: "string",
          description: "Start time (HH:mm)",
        },
        end: {
          type: "string",
          description: "End time (HH:mm)",
        },
        frequency: {
          type: "string",
          enum: ["weekly", "biweekly", "every_3_weeks", "every_4_weeks"],
          description: "How often the shift repeats",
        },
        endType: {
          type: "string",
          enum: ["never", "after_months", "after_years", "on_date"],
          description: "When the series ends",
        },
        endValue: {
          type: ["integer", "string"],
          description: "For after_months/after_years: number of months/years. For on_date: end date (YYYY-MM-DD).",
        },
      },
      required: ["weekday", "anchorDate", "start", "end", "frequency", "endType"],
    },
    input_examples: [
      // Weekly Monday shift 9-5, runs forever
      {
        weekday: 1,
        anchorDate: "2025-01-20",
        start: "09:00",
        end: "17:00",
        frequency: "weekly",
        endType: "never",
      },
      // Every Saturday 12-6pm for 3 months
      {
        weekday: 6,
        anchorDate: "2025-01-25",
        start: "12:00",
        end: "18:00",
        frequency: "weekly",
        endType: "after_months",
        endValue: 3,
      },
      // Biweekly Friday evening shift until end of year
      {
        weekday: 5,
        anchorDate: "2025-01-24",
        start: "18:00",
        end: "23:00",
        frequency: "biweekly",
        endType: "on_date",
        endValue: "2025-12-31",
      },
      // Every 3 weeks on Wednesday for 1 year
      {
        weekday: 3,
        anchorDate: "2025-01-22",
        start: "08:00",
        end: "16:00",
        frequency: "every_3_weeks",
        endType: "after_years",
        endValue: 1,
      },
    ],
  },

  {
    name: "confirm_series_shift",
    description: `Step 2 of 2: Actually create the recurring series after reviewing the draft.

Use the SAME parameters from draft_series_shift, plus conflictResolution to handle any conflicts.

IMPORTANT: Only call this after draft_series_shift. Use identical weekday, anchorDate, start, end, frequency, endType, and endValue.`,
    input_schema: {
      type: "object",
      properties: {
        weekday: {
          type: "integer",
          description: "Same weekday from draft (0-6)",
        },
        anchorDate: {
          type: "string",
          description: "Same anchor date from draft (YYYY-MM-DD)",
        },
        start: {
          type: "string",
          description: "Same start time from draft (HH:mm)",
        },
        end: {
          type: "string",
          description: "Same end time from draft (HH:mm)",
        },
        frequency: {
          type: "string",
          enum: ["weekly", "biweekly", "every_3_weeks", "every_4_weeks"],
          description: "Same frequency from draft",
        },
        endType: {
          type: "string",
          enum: ["never", "after_months", "after_years", "on_date"],
          description: "Same end type from draft",
        },
        endValue: {
          type: ["integer", "string"],
          description: "Same end value from draft (if applicable)",
        },
        conflictResolution: {
          type: "string",
          enum: ["keep_both", "skip_conflicts"],
          description: "keep_both: series coexists with conflicts. skip_conflicts: series skips dates with existing shifts.",
        },
      },
      required: ["weekday", "anchorDate", "start", "end", "frequency", "endType", "conflictResolution"],
    },
    input_examples: [
      // Confirm weekly Monday shift, skip conflicting dates
      {
        weekday: 1,
        anchorDate: "2025-01-20",
        start: "09:00",
        end: "17:00",
        frequency: "weekly",
        endType: "never",
        conflictResolution: "skip_conflicts",
      },
      // Confirm Saturday series, allow both shifts on conflict dates
      {
        weekday: 6,
        anchorDate: "2025-01-25",
        start: "12:00",
        end: "18:00",
        frequency: "weekly",
        endType: "after_months",
        endValue: 3,
        conflictResolution: "keep_both",
      },
    ],
  },

  {
    name: "manage_series_shift",
    description: `List, update, or delete existing recurring series.

For LIST: action="list" returns all series with their IDs and details
For UPDATE: action="update" + seriesId + fields to change
For DELETE: action="delete" + seriesId

IMPORTANT: Always list first to get series IDs before update/delete.`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["list", "update", "delete"],
          description: "The operation to perform",
        },
        seriesId: {
          type: "string",
          description: "Series ID (required for update/delete)",
        },
        weekday: {
          type: "integer",
          description: "New weekday (0-6) for update",
        },
        anchorDate: {
          type: "string",
          description: "New anchor date for update",
        },
        start: {
          type: "string",
          description: "New start time for update",
        },
        end: {
          type: "string",
          description: "New end time for update",
        },
        frequency: {
          type: "string",
          enum: ["weekly", "biweekly", "every_3_weeks", "every_4_weeks"],
          description: "New frequency for update",
        },
        endType: {
          type: "string",
          enum: ["never", "after_months", "after_years", "on_date"],
          description: "New end type for update",
        },
        endValue: {
          type: ["integer", "string"],
          description: "New end value for update",
        },
      },
      required: ["action"],
    },
    input_examples: [
      // List all recurring series
      {
        action: "list",
      },
      // Update series times
      {
        action: "update",
        seriesId: "abc123-def456",
        start: "10:00",
        end: "18:00",
      },
      // Change series to end after 6 months
      {
        action: "update",
        seriesId: "abc123-def456",
        endType: "after_months",
        endValue: 6,
      },
      // Delete a series
      {
        action: "delete",
        seriesId: "abc123-def456",
      },
    ],
  },

  {
    name: "manage_series_exclusion",
    description: `Add or remove a date exclusion from a recurring series.

Use this when a user wants to skip a specific occurrence (e.g., holiday) or restore a previously skipped date.`,
    input_schema: {
      type: "object",
      properties: {
        seriesId: {
          type: "string",
          description: "The series ID",
        },
        date: {
          type: "string",
          description: "Date to exclude or restore (YYYY-MM-DD)",
        },
        action: {
          type: "string",
          enum: ["add", "remove"],
          description: "add: exclude the date. remove: restore previously excluded date.",
        },
      },
      required: ["seriesId", "date", "action"],
    },
    input_examples: [
      // Skip a series occurrence on Christmas
      {
        seriesId: "abc123-def456",
        date: "2025-12-25",
        action: "add",
      },
      // Restore a previously excluded date
      {
        seriesId: "abc123-def456",
        date: "2025-12-25",
        action: "remove",
      },
    ],
  },

  // ---------------------------------------------------------------------------
  // STATISTICS & ANALYTICS
  // ---------------------------------------------------------------------------
  {
    name: "get_statistics",
    description: `Get statistics and analytics. Use this instead of calculating manually from shifts.

Available metrics:
- current_month: Earnings, hours, shifts for current month
- last_month: Same metrics for previous month
- year_to_date: Year total
- last_6_months: Monthly trend (6 data points)
- this_week: Daily breakdown Mon-Sun
- by_day_of_week: Average per weekday
- monthly_goal: Progress toward monthly goal
- supplement_breakdown: Base pay vs supplements`,
    input_schema: {
      type: "object",
      properties: {
        metric: {
          type: "string",
          enum: [
            "current_month",
            "last_month",
            "year_to_date",
            "last_6_months",
            "this_week",
            "by_day_of_week",
            "monthly_goal",
            "supplement_breakdown",
          ],
          description: "Which statistic to retrieve",
        },
        year: {
          type: "integer",
          description: "Optional: specific year (default: current)",
        },
        month: {
          type: "integer",
          description: "Optional: specific month 1-12 (default: current)",
        },
      },
      required: ["metric"],
    },
    input_examples: [
      // How much did I earn this month?
      { metric: "current_month" },
      // Compare to last month
      { metric: "last_month" },
      // Am I on track for my monthly goal?
      { metric: "monthly_goal" },
      // Which day of the week do I earn most?
      { metric: "by_day_of_week" },
      // Show earnings trend over last 6 months
      { metric: "last_6_months" },
    ],
  },

  // ---------------------------------------------------------------------------
  // SETTINGS
  // ---------------------------------------------------------------------------
  {
    name: "manage_settings",
    description: `View or update user settings.

For VIEW: call with no parameters or action="view" to see all settings
For UPDATE: action="update" + category + settings object with key-value pairs

Categories:
- display: theme, defaultShiftsView
- payroll: pauseDeductionEnabled, pauseDeductionMethod, pauseThresholdHours, pauseDeductionMinutes
- tax: taxDeductionEnabled, taxPercentage, halfTaxMonth
- goals: monthlyGoal, payrollDay
- preferences: directTimeInput, fullMinuteRange`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["view", "update"],
          description: "view (default) or update",
        },
        category: {
          type: "string",
          enum: ["display", "payroll", "tax", "goals", "preferences"],
          description: "Settings category to update",
        },
        settings: {
          type: "object",
          description: "Key-value pairs to update",
        },
      },
    },
    input_examples: [
      // View all current settings
      {},
      // Change to dark mode
      {
        action: "update",
        category: "display",
        settings: { theme: "dark" },
      },
      // Set monthly goal to 50000 kr
      {
        action: "update",
        category: "goals",
        settings: { monthlyGoal: 50000 },
      },
      // Enable tax deduction at 35%
      {
        action: "update",
        category: "tax",
        settings: { taxDeductionEnabled: true, taxPercentage: 35 },
      },
    ],
  },
];

/**
 * Tool name type
 */
export type ToolName =
  | "manage_shift"
  | "query_shifts"
  | "calculate_wages"
  | "draft_series_shift"
  | "confirm_series_shift"
  | "manage_series_shift"
  | "manage_series_exclusion"
  | "get_statistics"
  | "manage_settings";

/**
 * Tool result type
 */
export type ToolResult = {
  success: boolean;
  message: string;
  data?: unknown;
};
