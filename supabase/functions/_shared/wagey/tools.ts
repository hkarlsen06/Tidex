/**
 * Wagey Chat Tools
 *
 * Tool definitions for AI agent to manage shifts.
 * input_examples are preserved and folded into OpenAI tool descriptions at runtime.
 */

import { z } from "npm:zod";
import type { FunctionTool } from "./ai-types.ts";

// =============================================================================
// ZOD SCHEMAS (for validation in executor)
// =============================================================================

/**
 * Short ID schema - accepts 4-8 hex chars (short ID) or full UUID
 */
const shortOrFullId = z.string().regex(/^[a-f0-9]{4,8}$|^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i);

/**
 * Manage Shift Tool Schema
 */
export const manageShiftSchema = z.object({
  action: z.enum(["create", "update", "delete"]),
  // Create action
  dates: z.array(z.string().regex(/^\d{4}-\d{2}-\d{2}$/)).min(1).optional(),
  start: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  end: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  // Optional workplace/job for create (full UUID from list_workplaces)
  jobId: z.string().uuid().optional(),
  // Update/delete action - accepts short IDs (5 chars) or full UUIDs
  shiftId: shortOrFullId.optional(),
  shiftIds: z.array(shortOrFullId).min(1).optional(),
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
  sortBy: z
    .enum(["date_latest", "date_earliest", "date", "earnings", "hours"])
    .optional()
    .default("date_latest"),
  // Optional workplace/job filter (full UUID from list_workplaces)
  jobId: z.string().uuid().optional(),
});

export type QueryShiftsInput = z.infer<typeof queryShiftsSchema>;

/**
 * Calculate Wages Tool Schema
 */
export const calculateWagesSchema = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  // Optional workplace/job filter (full UUID from list_workplaces)
  jobId: z.string().uuid().optional(),
});

export type CalculateWagesInput = z.infer<typeof calculateWagesSchema>;

/**
 * Weekday with anchor date for recurring shifts
 */
const weekdayAnchorSchema = z.object({
  day: z.number().int().min(0).max(6),
  anchorDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});

/**
 * Draft Recurring Shift Tool Schema (Step 1 of 2)
 * Supports multiple weekdays in a single recurring shift (e.g., Mon/Wed/Fri)
 */
export const draftRecurringShiftSchema = z.object({
  weekdays: z.array(weekdayAnchorSchema).min(1).max(7),
  start: z.string().regex(/^\d{2}:\d{2}$/),
  end: z.string().regex(/^\d{2}:\d{2}$/),
  frequency: z.enum(["weekly", "biweekly", "every_3_weeks", "every_4_weeks"]),
  endType: z.enum(["never", "after_months", "after_years", "on_date"]),
  endValue: z.union([z.number().int().min(1), z.string().regex(/^\d{4}-\d{2}-\d{2}$/)]).optional(),
});

export type DraftRecurringShiftInput = z.infer<typeof draftRecurringShiftSchema>;

/**
 * Confirm Recurring Shift Tool Schema (Step 2 of 2)
 * Supports multiple weekdays in a single recurring shift (e.g., Mon/Wed/Fri)
 */
export const confirmRecurringShiftSchema = z.object({
  weekdays: z.array(weekdayAnchorSchema).min(1).max(7),
  start: z.string().regex(/^\d{2}:\d{2}$/),
  end: z.string().regex(/^\d{2}:\d{2}$/),
  frequency: z.enum(["weekly", "biweekly", "every_3_weeks", "every_4_weeks"]),
  endType: z.enum(["never", "after_months", "after_years", "on_date"]),
  endValue: z.union([z.number().int().min(1), z.string().regex(/^\d{4}-\d{2}-\d{2}$/)]).optional(),
  conflictResolution: z.enum(["keep_both", "skip_conflicts"]),
});

export type ConfirmRecurringShiftInput = z.infer<typeof confirmRecurringShiftSchema>;

/**
 * Manage Recurring Shift Tool Schema
 */
export const manageRecurringShiftSchema = z.object({
  action: z.enum(["list", "update", "delete"]),
  recurringId: shortOrFullId.optional(),
  // Update fields - use weekdays array to replace all weekdays
  weekdays: z.array(weekdayAnchorSchema).min(1).max(7).optional(),
  start: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  end: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  frequency: z.enum(["weekly", "biweekly", "every_3_weeks", "every_4_weeks"]).optional(),
  endType: z.enum(["never", "after_months", "after_years", "on_date"]).optional(),
  endValue: z.union([z.number().int().min(1), z.string().regex(/^\d{4}-\d{2}-\d{2}$/)]).optional(),
});

export type ManageRecurringShiftInput = z.infer<typeof manageRecurringShiftSchema>;

/**
 * Manage Recurring Exclusion Tool Schema
 */
export const manageRecurringExclusionSchema = z.object({
  recurringId: shortOrFullId,
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  action: z.enum(["add", "remove"]),
});

export type ManageRecurringExclusionInput = z.infer<typeof manageRecurringExclusionSchema>;

/**
 * Get Statistics Tool Schema
 */
export const getStatisticsSchema = z.object({
  metric: z.enum([
    "current_month",
    "last_month",
    "year_to_date",
    "full_year",
    "yearly_months",
    "this_week",
    "monthly_goal",
    "supplement_breakdown",
  ]),
  year: z.number().int().min(2020).max(2100).optional(),
  month: z.number().int().min(1).max(12).optional(),
  // Optional workplace/job filter (full UUID from list_workplaces)
  jobId: z.string().uuid().optional(),
});

export type GetStatisticsInput = z.infer<typeof getStatisticsSchema>;

/**
 * Manage Settings Tool Schema
 */
export const manageSettingsSchema = z.object({
  action: z.enum(["view", "update"]).optional().default("view"),
  category: z.enum(["display", "tax", "goals", "preferences"]).optional(),
  settings: z.record(z.string(), z.any()).optional(),
});

export type ManageSettingsInput = z.infer<typeof manageSettingsSchema>;

/**
 * List Workplaces Tool Schema
 */
export const listWorkplacesSchema = z.object({
  includeArchived: z.boolean().optional().default(true),
});

export type ListWorkplacesInput = z.infer<typeof listWorkplacesSchema>;

/**
 * Manage Workplace Tool Schema
 */
export const manageWorkplaceSchema = z.object({
  action: z.enum([
    "create",
    "update",
    "archive",
    "unarchive",
    "set_default",
    "reorder",
    "delete",
  ]),
  // Required for update/archive/unarchive/set_default/delete
  jobId: z.string().uuid().optional(),
  // Create/update fields
  name: z.string().min(1).max(100).optional(),
  color: z.union([z.string().regex(/^#[0-9a-fA-F]{6}$/), z.null()]).optional(),
  payrollDay: z.number().int().min(1).max(31).optional(),
  halfTaxMonth: z.union([z.literal(11), z.literal(12), z.null()]).optional(),
  monthlyGoal: z.number().int().min(0).nullable().optional(),
  // Required for reorder
  direction: z.enum(["up", "down"]).optional(),
});

export type ManageWorkplaceInput = z.infer<typeof manageWorkplaceSchema>;

/**
 * List Friends Tool Schema
 */
export const listFriendsSchema = z.object({
  includeBlocked: z.boolean().optional().default(true),
});

export type ListFriendsInput = z.infer<typeof listFriendsSchema>;

/**
 * Manage Friend Sharing Tool Schema
 */
export const manageFriendSharingSchema = z.object({
  action: z.enum([
    "share_by_identifier",
    "share_back",
    "remove_recipient",
    "toggle_recipient_earnings",
    "block_sharer",
    "unblock_sharer",
    "set_sharer_muted",
    "remove_sharer",
  ]),
  identifier: z.string().optional(),
  friendId: z.string().uuid().optional(),
  showEarnings: z.boolean().optional(),
  muted: z.boolean().optional(),
});

export type ManageFriendSharingInput = z.infer<typeof manageFriendSharingSchema>;

/**
 * Query Friend Shifts Tool Schema
 */
export const queryFriendShiftsSchema = z.object({
  friendId: z.string().uuid(),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  limit: z.number().int().min(1).max(100).optional().default(30),
  minTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  maxTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  weekdays: z.array(z.number().int().min(0).max(6)).optional(),
  sortBy: z
    .enum(["date_latest", "date_earliest", "date", "earnings", "hours"])
    .optional()
    .default("date_latest"),
  jobId: z.string().uuid().optional(),
});

export type QueryFriendShiftsInput = z.infer<typeof queryFriendShiftsSchema>;

/**
 * Query Friend Featured Shift Tool Schema
 * Reuses the same featured-shift preview logic as sharing UI.
 */
export const queryFriendFeaturedShiftSchema = z.object({
  friendId: z.string().uuid(),
});

export type QueryFriendFeaturedShiftInput = z.infer<typeof queryFriendFeaturedShiftSchema>;

/**
 * Manage Shift Advanced Tool Schema
 */
export const manageShiftAdvancedSchema = z.object({
  action: z.enum([
    "copy_shifts",
    "update_custom_supplements",
    "convert_recurring_to_standalone",
    "move_recurring_occurrence",
    "clear_shift_snapshots",
  ]),
  shiftIds: z.array(z.string().min(1)).min(1).optional(),
  targetDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  shiftId: z.string().min(1).optional(),
  customSupplements: z.any().optional(),
  recurringId: shortOrFullId.optional(),
  shiftDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  startTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  endTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  sourceDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

export type ManageShiftAdvancedInput = z.infer<typeof manageShiftAdvancedSchema>;

/**
 * Manage Feedback Tool Schema
 */
export const manageFeedbackSchema = z.object({
  action: z.enum(["submit", "list"]),
  message: z.string().optional(),
});

export type ManageFeedbackInput = z.infer<typeof manageFeedbackSchema>;

/**
 * Manage Profile Tool Schema
 */
export const manageProfileSchema = z.object({
  action: z.enum(["view", "update_name"]),
  firstName: z.string().max(100).optional(),
});

export type ManageProfileInput = z.infer<typeof manageProfileSchema>;

/**
 * Get Wage Info Tool Schema
 * Returns user's complete wage configuration with temporal context
 */
export const getWageInfoSchema = z.object({
  // Optional workplace/job context (full UUID from list_workplaces)
  jobId: z.string().uuid().optional(),
});

export type GetWageInfoInput = z.infer<typeof getWageInfoSchema>;

/**
 * Supplement rule schema for wage snapshots
 */
const supplementRuleSchema = z.object({
  days: z.array(z.number().int().min(1).max(7)),
  from: z.string().regex(/^\d{2}:\d{2}$/),
  to: z.string().regex(/^\d{2}:\d{2}$/),
  rate: z.number().positive().optional(),
  percent: z.number().positive().optional(),
});

// Backward-compatible alias shape used by some tool generations:
// { startTime, endTime, amount } => { from, to, rate }
const supplementRuleAliasSchema = z.object({
  days: z.array(z.number().int().min(1).max(7)),
  startTime: z.string().regex(/^\d{2}:\d{2}$/),
  endTime: z.string().regex(/^\d{2}:\d{2}$/),
  amount: z.number().positive().optional(),
  rate: z.number().positive().optional(),
  percent: z.number().positive().optional(),
  type: z.string().optional(),
});

/**
 * Manage Wage Snapshots Tool Schema
 * Allows CRUD operations on wage snapshots (wage history entries)
 */
export const manageWageSnapshotsSchema = z.object({
  action: z.enum(["create", "update", "delete"]),
  // Optional workplace/job context for create (full UUID from list_workplaces)
  jobId: z.string().uuid().optional(),
  // For update/delete - accepts short IDs (4-8 hex chars) or full UUIDs
  snapshot_id: shortOrFullId.optional(),
  // For create - required date when the new rates take effect
  from_date: z.union([z.string().regex(/^\d{4}-\d{2}-\d{2}$/), z.null()]).optional(),
  // Wage settings - all optional for update (only include fields to change)
  hourly_wage: z.number().positive().optional(),
  wage_level: z.number().int().min(1).max(9).nullable().optional(),
  // Tax settings
  tax_enabled: z.boolean().optional(),
  tax_percentage: z.number().min(0).max(100).optional(),
  // Break deduction settings
  break_enabled: z.boolean().optional(),
  break_method: z.enum(["proportional", "base_only", "end_of_shift", "none"]).optional(),
  break_threshold_hours: z.number().positive().optional(),
  break_deduction_minutes: z.number().int().min(0).optional(),
  // Supplements - "copy_current" copies from current snapshot, or provide array of rules
  supplements: z.union([
    z.literal("copy_current"),
    z.array(z.union([supplementRuleSchema, supplementRuleAliasSchema])),
  ]).optional(),
});

export type ManageWageSnapshotsInput = z.infer<typeof manageWageSnapshotsSchema>;

/**
 * Hypothetical shift scenario for earnings calculation
 */
const hypotheticalShiftSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  start_time: z.string().regex(/^\d{2}:\d{2}$/),
  end_time: z.string().regex(/^\d{2}:\d{2}$/),
  label: z.string().optional(),
});

/**
 * Calculate Earnings Tool Schema
 * Supports three modes:
 * - hypothetical: Calculate earnings for a shift that doesn't exist
 * - compare: Compare multiple hypothetical scenarios side-by-side
 * - hypothetical_change: "What if I changed this existing shift?"
 */
export const calculateEarningsSchema = z.object({
  // Mode 1: Single hypothetical shift
  hypothetical: hypotheticalShiftSchema.optional(),
  // Mode 2: Compare multiple scenarios
  compare: z.array(hypotheticalShiftSchema).min(2).max(5).optional(),
  // Mode 3: What-if on existing shift
  hypothetical_change: z.object({
    // Accept: short hex IDs (4-8 chars), full UUIDs, or compact virtual shift IDs (virtual-{5char}-YYYY-MM-DD)
    shift_id: z.string().regex(/^[a-f0-9]{4,8}$|^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$|^virtual-[a-f0-9]{5}-\d{4}-\d{2}-\d{2}$/i),
    changes: z.object({
      start_time: z.string().regex(/^\d{2}:\d{2}$/).optional(),
      end_time: z.string().regex(/^\d{2}:\d{2}$/).optional(),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    }),
  }).optional(),
}).refine(
  (data) => {
    // Exactly one mode must be specified
    const modes = [data.hypothetical, data.compare, data.hypothetical_change].filter(Boolean);
    return modes.length === 1;
  },
  { message: "Exactly one mode must be specified: hypothetical, compare, or hypothetical_change" }
);

export type CalculateEarningsInput = z.infer<typeof calculateEarningsSchema>;

// =============================================================================
// TOOL DEFINITIONS (provider-neutral format with input_examples)
// =============================================================================

export const tools: FunctionTool[] = [
  // ---------------------------------------------------------------------------
  // SHIFT MANAGEMENT
  // ---------------------------------------------------------------------------
  {
    name: "manage_shift",
    description: `Create, update, or delete shifts.

Actions:
- CREATE: action="create", dates (array of YYYY-MM-DD), start (HH:mm), end (HH:mm)
- UPDATE: action="update", shiftId, plus fields to change (start, end, date)
- DELETE: action="delete", shiftId (single) or shiftIds (bulk delete)

Edge cases:
- Cross-midnight shifts: If end time is before start time (e.g., 22:00-06:00), the shift spans to the next day
- Multiple dates: Use dates array to create identical shifts on multiple days at once
- Update requires ID: Always query_shifts first to get the shift ID before updating/deleting
- Multiple workplaces: Use jobId (from list_workplaces) to assign a shift to a specific workplace. Omit for the user's default workplace.`,
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
        jobId: {
          type: "string",
          description: "Workplace/job UUID from list_workplaces. Only for create. Omit to use the default workplace.",
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
      // Update a shift's times (use short 5-char ID from query_shifts)
      {
        action: "update",
        shiftId: "a1b2c",
        start: "10:00",
        end: "18:00",
      },
      // Delete a single shift (use short 5-char ID from query_shifts)
      {
        action: "delete",
        shiftId: "a1b2c",
      },
      // Bulk delete multiple shifts
      {
        action: "delete",
        shiftIds: ["a1b2c", "d3e4f", "g5h6i"],
      },
    ],
  },

  {
    name: "query_shifts",
    description: `Get shifts with optional filters. Returns shift IDs needed for update/delete operations.

Default behavior: Without parameters, returns shifts for the current week.

Important:
- For aggregate summaries, use get_statistics first and use query_shifts only when you need itemized shift rows
- Use null for optional filters you are not using
- Never send empty strings for startDate, endDate, minTime, maxTime, or jobId

Response includes:
- data: Array of shifts with id, date, day, start, end, hours, gross, net (if tax enabled), and workplace (name of the job/workplace)
- summary: Aggregated statistics (shiftCount, totalHours, totalGross, totalNet, avgHoursPerShift, avgGrossPerShift)
- currency: User's selected currency

Filters:
- Date range: startDate and endDate (YYYY-MM-DD)
- Time of day: minTime/maxTime filter by shift start time
- Weekdays: array of day numbers (0=Sunday through 6=Saturday)
- Workplace: jobId (UUID from list_workplaces) to filter to one workplace
- Sorting:
  - date_latest (default): newest first
  - date_earliest: oldest first
  - earnings: highest first
  - hours: highest first
  - date: legacy alias for date_latest

Use cases:
- Before update/delete: Query to get shift IDs
- Finding specific shifts: Use filters to narrow down results
- Analytics: Sort by earnings to find highest-paying shifts
- Period overview: Use summary for quick totals without separate calculate_wages call
- Workplace breakdown: Omit jobId to see all shifts with their workplace labels`,
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
          description: "Only shifts starting at or after this time (HH:mm). Use null if no lower time filter is needed; never send an empty string.",
        },
        maxTime: {
          type: "string",
          description: "Only shifts starting at or before this time (HH:mm). Use null if no upper time filter is needed; never send an empty string.",
        },
        weekdays: {
          type: "array",
          items: { type: "integer" },
          description: "Filter by weekday (see weekday_reference in system prompt)",
        },
        sortBy: {
          type: "string",
          enum: ["date_latest", "date_earliest", "date", "earnings", "hours"],
          description: "Sort order (default: date_latest; date is a legacy alias for date_latest)",
        },
        jobId: {
          type: "string",
          description: "Filter to a specific workplace/job (UUID from list_workplaces)",
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

Required: Both startDate and endDate (YYYY-MM-DD format).

Returns:
- Gross pay (before tax)
- Net pay (after tax, if tax settings are configured)
- Total hours worked
- Tax deducted
- Number of shifts in the period

Optional: Use jobId (UUID from list_workplaces) to calculate wages for a specific workplace only.

Note: For quick monthly/yearly totals, prefer get_statistics which is optimized for common time periods.`,
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
        jobId: {
          type: "string",
          description: "Filter to a specific workplace/job (UUID from list_workplaces)",
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
  // RECURRING SHIFTS (2-step: draft then confirm)
  // ---------------------------------------------------------------------------
  {
    name: "draft_recurring_shift",
    description: `Step 1 of 2: Preview a recurring shift pattern WITHOUT creating it.

Purpose: Validates the pattern and checks for conflicts with existing shifts before committing.

Required parameters:
- weekdays: Array of {day, anchorDate} objects. Day uses weekday numbers (see weekday_reference). anchorDate (YYYY-MM-DD) MUST fall on that weekday and determines which week the recurring shift starts from.
- start/end: Times in HH:mm format
- frequency: weekly, biweekly, every_3_weeks, or every_4_weeks
- endType: never, after_months, after_years, or on_date (with endValue)

IMPORTANT: Use weekdays array to create a SINGLE recurring shift with multiple weekdays (e.g., Mon/Wed/Fri). Do NOT create separate recurring shifts for each day.

Anchor date offsets for alternating patterns:
When using biweekly (or every_N_weeks) frequency with multiple weekdays, the anchorDates control WHICH WEEKS each day falls on. If all anchorDates are in the same week, all days occur together. If anchorDates are offset by one week, the days ALTERNATE between weeks. Example: biweekly Thu (anchor week 33) + Fri (anchor week 34) = Thu week 33, Fri week 34, Thu week 35, Fri week 36, etc.

Workflow: After this returns conflict info, ask user how to handle conflicts, then call confirm_recurring_shift.`,
    input_schema: {
      type: "object",
      properties: {
        weekdays: {
          type: "array",
          items: {
            type: "object",
            properties: {
              day: {
                type: "integer",
                description: "Day of week (see weekday_reference)",
              },
              anchorDate: {
                type: "string",
                description: "Start date (YYYY-MM-DD). Must fall on the correct weekday. Determines which week THIS weekday starts from — each weekday can have a different anchor week to create alternating patterns.",
              },
            },
            required: ["day", "anchorDate"],
          },
          minItems: 1,
          maxItems: 7,
          description: "Array of weekdays with their anchor dates. Use multiple entries for multi-day patterns (same week: Mon/Wed/Fri; alternating weeks: offset anchorDates by one week).",
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
          description: "When the recurring shift ends",
        },
        endValue: {
          type: ["integer", "string"],
          description: "For after_months/after_years: number of months/years. For on_date: end date (YYYY-MM-DD).",
        },
      },
      required: ["weekdays", "start", "end", "frequency", "endType"],
    },
    input_examples: [
      // Weekly Monday shift 9-5, runs forever (single weekday)
      {
        weekdays: [{ day: 1, anchorDate: "2025-01-20" }],
        start: "09:00",
        end: "17:00",
        frequency: "weekly",
        endType: "never",
      },
      // Mon/Wed/Fri weekly shifts (multiple weekdays in ONE recurring shift)
      {
        weekdays: [
          { day: 1, anchorDate: "2025-01-20" },
          { day: 3, anchorDate: "2025-01-22" },
          { day: 5, anchorDate: "2025-01-24" },
        ],
        start: "09:00",
        end: "17:00",
        frequency: "weekly",
        endType: "after_months",
        endValue: 6,
      },
      // All weekdays (Mon-Fri) for full-time work schedule
      {
        weekdays: [
          { day: 1, anchorDate: "2025-01-20" },
          { day: 2, anchorDate: "2025-01-21" },
          { day: 3, anchorDate: "2025-01-22" },
          { day: 4, anchorDate: "2025-01-23" },
          { day: 5, anchorDate: "2025-01-24" },
        ],
        start: "08:00",
        end: "16:00",
        frequency: "weekly",
        endType: "never",
      },
      // Weekend shifts (Sat/Sun)
      {
        weekdays: [
          { day: 6, anchorDate: "2025-01-25" },
          { day: 0, anchorDate: "2025-01-26" },
        ],
        start: "10:00",
        end: "18:00",
        frequency: "weekly",
        endType: "after_months",
        endValue: 3,
      },
      // Alternating weeks: Thursday one week, Friday the next (biweekly with offset anchors)
      {
        weekdays: [
          { day: 4, anchorDate: "2025-01-16" },
          { day: 5, anchorDate: "2025-01-24" },
        ],
        start: "12:00",
        end: "19:00",
        frequency: "biweekly",
        endType: "after_months",
        endValue: 6,
      },
    ],
  },

  {
    name: "confirm_recurring_shift",
    description: `Step 2 of 2: Actually create the recurring shift after reviewing the draft.

IMPORTANT: Only call this AFTER draft_recurring_shift. Use identical parameters from the draft.

Required: All the same parameters from draft_recurring_shift, PLUS:
- conflictResolution: "keep_both" (recurring shift coexists with existing shifts) or "skip_conflicts" (recurring shift skips dates with existing shifts)

The recurring shift will be created and shifts generated according to the pattern.`,
    input_schema: {
      type: "object",
      properties: {
        weekdays: {
          type: "array",
          items: {
            type: "object",
            properties: {
              day: {
                type: "integer",
                description: "Day of week (see weekday_reference)",
              },
              anchorDate: {
                type: "string",
                description: "Start date (YYYY-MM-DD). Must fall on the correct weekday. Determines which week the recurring shift starts from.",
              },
            },
            required: ["day", "anchorDate"],
          },
          minItems: 1,
          maxItems: 7,
          description: "Same weekdays array from draft.",
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
          description: "keep_both: recurring shift coexists with conflicts. skip_conflicts: recurring shift skips dates with existing shifts.",
        },
      },
      required: ["weekdays", "start", "end", "frequency", "endType", "conflictResolution"],
    },
    input_examples: [
      // Confirm weekly Monday shift, skip conflicting dates
      {
        weekdays: [{ day: 1, anchorDate: "2025-01-20" }],
        start: "09:00",
        end: "17:00",
        frequency: "weekly",
        endType: "never",
        conflictResolution: "skip_conflicts",
      },
      // Confirm Mon/Wed/Fri recurring shift, allow both shifts on conflict dates
      {
        weekdays: [
          { day: 1, anchorDate: "2025-01-20" },
          { day: 3, anchorDate: "2025-01-22" },
          { day: 5, anchorDate: "2025-01-24" },
        ],
        start: "09:00",
        end: "17:00",
        frequency: "weekly",
        endType: "after_months",
        endValue: 6,
        conflictResolution: "keep_both",
      },
    ],
  },

  {
    name: "manage_recurring_shift",
    description: `List, update, or delete existing recurring shifts.

Actions:
- LIST: action="list" - Returns all recurring shifts with IDs, patterns, and schedules (weekdays array format)
- UPDATE: action="update", recurringId, plus fields to change (weekdays, times, frequency, endType)
- DELETE: action="delete", recurringId - Removes the recurring shift and ALL its virtual shifts disappear immediately

Workflow: Always LIST first to get recurring shift IDs before update/delete.

Note: Recurring shifts are virtual (not stored individually). Deleting a recurring shift removes all future occurrences.
Only standalone shifts (manually created or converted) remain after deletion.
When updating weekdays, provide the complete weekdays array (replaces all existing weekdays).`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["list", "update", "delete"],
          description: "The operation to perform",
        },
        recurringId: {
          type: "string",
          description: "Recurring shift ID (required for update/delete)",
        },
        weekdays: {
          type: "array",
          items: {
            type: "object",
            properties: {
              day: {
                type: "integer",
                description: "Day of week (see weekday_reference)",
              },
              anchorDate: {
                type: "string",
                description: "Start date (YYYY-MM-DD). Must fall on the correct weekday. Determines which week the recurring shift starts from.",
              },
            },
            required: ["day", "anchorDate"],
          },
          minItems: 1,
          maxItems: 7,
          description: "New weekdays for update (replaces all existing weekdays)",
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
      // List all recurring shifts
      {
        action: "list",
      },
      // Update recurring shift times (use short 5-char ID from list)
      {
        action: "update",
        recurringId: "a1b2c",
        start: "10:00",
        end: "18:00",
      },
      // Change recurring shift weekdays from Mon only to Mon/Wed/Fri
      {
        action: "update",
        recurringId: "a1b2c",
        weekdays: [
          { day: 1, anchorDate: "2025-01-20" },
          { day: 3, anchorDate: "2025-01-22" },
          { day: 5, anchorDate: "2025-01-24" },
        ],
      },
      // Change recurring shift to end after 6 months
      {
        action: "update",
        recurringId: "a1b2c",
        endType: "after_months",
        endValue: 6,
      },
      // Delete a recurring shift
      {
        action: "delete",
        recurringId: "a1b2c",
      },
    ],
  },

  {
    name: "manage_recurring_exclusion",
    description: `Add or remove a date exclusion from a recurring shift.

Use cases:
- Skip a specific occurrence (e.g., holiday, vacation day)
- Restore a previously skipped date

Actions:
- add: Exclude the date from the recurring shift (shift won't appear)
- remove: Restore a previously excluded date

Note: The date must be one that would normally occur in the recurring shift pattern.`,
    input_schema: {
      type: "object",
      properties: {
        recurringId: {
          type: "string",
          description: "The recurring shift ID",
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
      required: ["recurringId", "date", "action"],
    },
    input_examples: [
      // Skip a recurring shift occurrence on Christmas (use short 5-char ID from list)
      {
        recurringId: "a1b2c",
        date: "2025-12-25",
        action: "add",
      },
      // Restore a previously excluded date
      {
        recurringId: "a1b2c",
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
    description: `Get pre-computed statistics and analytics. Always prefer this over manual calculations.

Preferred first tool for summary questions about earnings, hours, or shift counts over a week, month, or year.
Use query_shifts only if the user also wants the individual shift rows.

Available metrics:
- current_month: Earnings, hours, shift count for current month
- last_month: Same metrics for previous month (good for comparison)
- year_to_date: Cumulative totals from Jan 1 up to today's date. For past years, uses same day-of-year as today (e.g., if today is Feb 4 2026, YTD for 2025 = Jan 1 - Feb 4 2025). Good for "same point in time" comparisons.
- full_year: Complete calendar year totals (Jan 1 - Dec 31). Use for "how much did I earn in total last year" questions.
- yearly_months: Monthly breakdown for all 12 months of the specified year. Returns array of {month, earnings, hours, shifts} for Jan-Dec. Use for trends, charts, or "show me my earnings by month".
- this_week: Daily breakdown Monday through Sunday
- monthly_goal: Progress toward user's monthly goal (if set)
- supplement_breakdown: How much is base pay vs evening/weekend supplements

When to use year_to_date vs full_year:
- "How much had I earned by this point last year?" → year_to_date with year parameter
- "How much did I earn in total last year?" → full_year with year parameter

Optional: year and month parameters to query specific periods (defaults to current).
Optional: jobId (UUID from list_workplaces) to get statistics for a specific workplace only.`,
    input_schema: {
      type: "object",
      properties: {
        metric: {
          type: "string",
          enum: [
            "current_month",
            "last_month",
            "year_to_date",
            "full_year",
            "yearly_months",
            "this_week",
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
        jobId: {
          type: "string",
          description: "Filter to a specific workplace/job (UUID from list_workplaces)",
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
      // Show monthly breakdown for the year
      { metric: "yearly_months" },
      // How much had I earned by this point last year?
      { metric: "year_to_date", year: 2025 },
      // How many hours did I work in total last year / in 2025?
      { metric: "full_year", year: 2025 },
    ],
  },

  // ---------------------------------------------------------------------------
  // SETTINGS
  // ---------------------------------------------------------------------------
  {
    name: "manage_settings",
    description: `View or update user settings (NOT wages - use get_wage_info for wage/tax/pause history).

Actions:
- VIEW: No parameters or action="view" - Returns display, goals, preferences, and tax (halfTaxMonth only)
- UPDATE: action="update", category, settings object with key-value pairs

Categories and keys:
- display: theme, defaultShiftsView, currency (e.g., "kr", "$", "€", "£"), showDashboardClockButtons (boolean)
- tax: halfTaxMonth (1-12, global half-tax month override)
- goals: monthlyGoal (baseline for all months), payrollDay (1-31), monthlyGoalsByMonth (per-month overrides, see below)
- preferences: directTimeInput, fullMinuteRange, defaultStartupTab ("home"|"shifts"|"add"|"stats"|"sharing")

Per-month goal overrides (monthlyGoalsByMonth):
- Provide a map of { "YYYY-MM": amount } to set overrides for specific months
- Use null as the value to remove an override and fall back to monthlyGoal baseline
- Example: { "2026-03": 45000 } sets only March; other months keep the baseline
- The view response shows monthlyGoalsByMonth (all overrides) and the effective monthlyGoal for this month

Note: Only include settings you want to change in the settings object.
Note: Tax deduction enabled/percentage are per-snapshot — use get_wage_info instead.`,
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
          enum: ["display", "tax", "goals", "preferences"],
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
      // Change currency to dollars
      {
        action: "update",
        category: "display",
        settings: { currency: "$" },
      },
      // Change currency to euros
      {
        action: "update",
        category: "display",
        settings: { currency: "€" },
      },
      // Set monthly goal to 50000 kr
      {
        action: "update",
        category: "goals",
        settings: { monthlyGoal: 50000 },
      },
      // Set the half tax month (global setting)
      {
        action: "update",
        category: "tax",
        settings: { halfTaxMonth: 12 },
      },
      // Set a per-month goal override for March 2026
      {
        action: "update",
        category: "goals",
        settings: { monthlyGoalsByMonth: { "2026-03": 45000 } },
      },
      // Remove a per-month override (fall back to baseline)
      {
        action: "update",
        category: "goals",
        settings: { monthlyGoalsByMonth: { "2026-03": null } },
      },
      // Hide dashboard clock buttons
      {
        action: "update",
        category: "display",
        settings: { showDashboardClockButtons: false },
      },
      // Change startup tab to stats
      {
        action: "update",
        category: "preferences",
        settings: { defaultStartupTab: "stats" },
      },
    ],
  },

  // ---------------------------------------------------------------------------
  // WAGE INFO
  // ---------------------------------------------------------------------------
  {
    name: "get_wage_info",
    description: `Get wage configuration for a workplace (job): snapshot history plus pay settings.

Returns:
- workplace: Selected workplace context (id, name, isDefault) when available
- globalPaySettings: Pay configuration for the selected workplace when available (falls back to legacy/global settings)
- tariffs: Distinct tariff agreements referenced by the workplace's wage snapshots (id, displayName, description, country, isDefault)
- current: The wage that applies today (id, fromDate, usingTariff, wageLevel, tariffTypeId, tariff, hourlyWage, supplements, taxEnabled, taxPercentage)
- upcoming: Future scheduled wage changes (if any) - compact format showing only changed fields, includes id
- history: Past wage entries for context (if any) - compact format showing only changed fields, includes id

Input:
- Optional jobId (UUID from list_workplaces)
- If omitted, defaults to the user's default workplace

Use this when the user asks about their wage, hourly rate, tax settings, payroll day, or wage history.
For display/preference settings (theme, defaultStartupTab, etc.), use manage_settings instead.
To modify wage entries, use manage_wage_snapshots with the id from get_wage_info.
To modify halfTaxMonth or payrollDay, use manage_settings with category="tax" or category="goals".`,
    input_schema: {
      type: "object",
      properties: {
        jobId: {
          type: "string",
          description: "Optional workplace/job UUID from list_workplaces. Defaults to the default workplace.",
        },
      },
    },
    input_examples: [
      {},
      { jobId: "5f5e8f67-8d36-4e47-bdb0-9ad6f2367d28" },
    ],
  },

  {
    name: "manage_wage_snapshots",
    description: `Create, update, or delete wage snapshots (wage history entries).

Wage snapshots define the user's hourly wage, tax settings, break deduction, and supplements for a specific time period.
Each snapshot has a from_date (when it takes effect) - the baseline snapshot has from_date=null.

Actions:
- CREATE: Creates a new wage entry. Requires from_date and tax_enabled. If tax_enabled=true, tax_percentage is required. Other fields are COPIED from current snapshot by default - only include fields you want to CHANGE.
- UPDATE: Updates an existing wage entry. Requires snapshot_id (use short ID from get_wage_info). Only include fields to change.
- DELETE: Deletes a wage entry. Requires snapshot_id.

IMPORTANT - Dichotomy between tariff and custom rates:
- Snapshots are EITHER tariff-based OR custom hourly rate, never both
- If you provide hourly_wage → automatically switches to CUSTOM mode (wage_level becomes null)
- If you provide wage_level → automatically switches to TARIFF mode (hourly_wage is looked up from preset rates)
- You do NOT need to explicitly set wage_level to null when setting a custom hourly_wage

Other notes:
- Optional jobId for CREATE targets a specific workplace (UUID from list_workplaces). If omitted, default workplace is used.
- Always call get_wage_info first to see current configuration and get snapshot IDs
- For CREATE: ask for tax handling explicitly (tax_enabled and optionally tax_percentage) before calling
- For UPDATE: only specify fields to change
- Use supplements: "copy_current" to explicitly copy current supplements, or provide a new array of rules
- For end-of-day supplement windows, use 24:00 (preferred over 23:59)`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["create", "update", "delete"],
          description: "The operation to perform",
        },
        jobId: {
          type: "string",
          description: "Optional workplace/job UUID from list_workplaces (CREATE only). Defaults to the default workplace.",
        },
        snapshot_id: {
          type: "string",
          description: "Snapshot ID (required for update/delete). Use short ID from get_wage_info.",
        },
        from_date: {
          type: ["string", "null"],
          description: "Date when new rates take effect (YYYY-MM-DD). Required for create. Null = baseline.",
        },
        hourly_wage: {
          type: "number",
          description: "Hourly wage in NOK (e.g., 220.5). Only include to change.",
        },
        wage_level: {
          type: ["integer", "null"],
          description: "Wage level 1-9 (tariff-based). Set to null to use custom hourly_wage instead.",
        },
        tax_enabled: {
          type: "boolean",
          description: "Whether tax deduction is enabled for this period. Required for create.",
        },
        tax_percentage: {
          type: "number",
          description: "Tax percentage (0-100) for this period. Required for create when tax_enabled=true.",
        },
        break_enabled: {
          type: "boolean",
          description: "Whether break deduction is enabled.",
        },
        break_method: {
          type: "string",
          enum: ["proportional", "base_only", "end_of_shift", "none"],
          description: "Break deduction method.",
        },
        break_threshold_hours: {
          type: "number",
          description: "Hours before break deduction kicks in (e.g., 5.5).",
        },
        break_deduction_minutes: {
          type: "integer",
          description: "Minutes to deduct for break (e.g., 30).",
        },
        supplements: {
          type: ["string", "array"],
          items: {
            type: "object",
            properties: {
              days: {
                type: "array",
                items: { type: "integer" },
                description: "Weekday numbers 1-7 (Monday-Sunday)",
              },
              from: {
                type: "string",
                description: "Canonical start time (HH:mm)",
              },
              to: {
                type: "string",
                description: "Canonical end time (HH:mm, use 24:00 for end of day)",
              },
              startTime: {
                type: "string",
                description: "Alias for from (HH:mm)",
              },
              endTime: {
                type: "string",
                description: "Alias for to (HH:mm, use 24:00 for end of day)",
              },
              amount: {
                type: "number",
                description: "Alias for rate (fixed NOK per hour supplement)",
              },
              rate: {
                type: "number",
                description: "Fixed NOK per hour supplement",
              },
              percent: {
                type: "number",
                description: "Percentage supplement",
              },
              type: {
                type: "string",
                description: "Optional legacy metadata field; ignored by the executor",
              },
            },
            required: ["days"],
            description: "Supplement rule. Use canonical fields (days/from/to/rate or percent) or alias fields (days/startTime/endTime/amount or percent).",
          },
          description: '"copy_current" to copy from current snapshot, or array of supplement rules. Rule keys can be canonical (from/to/rate) or alias (startTime/endTime/amount).',
        },
      },
      required: ["action"],
    },
    input_examples: [
      // "From February I will have 5% tax"
      {
        action: "create",
        from_date: "2025-02-01",
        tax_enabled: true,
        tax_percentage: 5,
      },
      // "Update my current hourly wage to 250" (automatically switches to custom mode, wage_level becomes null)
      {
        action: "update",
        snapshot_id: "a1b2c",
        hourly_wage: 250,
      },
      // "Delete the upcoming wage change"
      {
        action: "delete",
        snapshot_id: "d3e4f",
      },
      // "From March I want wage level 6 with 10% tax" (automatically looks up hourly rate from tariff)
      {
        action: "create",
        from_date: "2025-03-01",
        wage_level: 6,
        tax_enabled: true,
        tax_percentage: 10,
      },
      // "Change from tariff to custom rate of 220" (hourly_wage triggers custom mode, no need to set wage_level: null)
      {
        action: "update",
        snapshot_id: "a1b2c",
        hourly_wage: 220,
      },
      // "Switch to wage level 4" (automatically looks up rate 193.05 from tariff)
      {
        action: "update",
        snapshot_id: "a1b2c",
        wage_level: 4,
      },
      // "Enable 30 minute break deduction starting from next month"
      {
        action: "create",
        from_date: "2025-02-01",
        break_enabled: true,
        break_method: "proportional",
        break_threshold_hours: 5.5,
        break_deduction_minutes: 30,
      },
    ],
  },

  // ---------------------------------------------------------------------------
  // HYPOTHETICAL EARNINGS CALCULATOR
  // ---------------------------------------------------------------------------
  {
    name: "calculate_earnings",
    description: `Calculate hypothetical earnings for shifts that don't exist yet. Perfect for "what if" questions.

THREE MODES (use exactly one):

1. HYPOTHETICAL: Calculate earnings for a single hypothetical shift
   - Use when: "How much would I earn working 15-23 on Monday?"
   - Params: hypothetical: { date, start_time, end_time }

2. COMPARE: Compare 2-5 hypothetical scenarios side-by-side
   - Use when: "Would I earn more working 12-18 or 16-22 on Friday?"
   - Params: compare: [{ date, start_time, end_time, label? }, ...]
   - Returns: All scenarios + which is best and by how much

3. HYPOTHETICAL_CHANGE: Calculate what would happen if an existing shift was different
   - Use when: "How much more would I earn if my Monday shift started at 15 instead of 9?"
   - Params: hypothetical_change: { shift_id, changes: { start_time?, end_time?, date? } }
   - Returns: Original vs modified earnings with difference
   - Note: Query the shift first to get its ID
   - Virtual/recurring shifts have IDs like "virtual-a1b2c-2025-12-03" (5-char recurring ID + date)

Returns for each scenario:
- gross: Total earnings before tax
- net: Earnings after tax (if tax settings configured)
- paid_hours: Hours after break deduction
- breakdown: base_pay, supplement_pay, break_deducted_minutes

The date matters for supplements (weekend/evening rates vary by day).

IMPORTANT: Always calculate specific YYYY-MM-DD dates from relative references like "Monday", "next Friday", "this weekend". Use today's date as reference to determine the exact calendar date.`,
    input_schema: {
      type: "object",
      properties: {
        hypothetical: {
          type: "object",
          properties: {
            date: { type: "string", description: "Date (YYYY-MM-DD)" },
            start_time: { type: "string", description: "Start time (HH:mm)" },
            end_time: { type: "string", description: "End time (HH:mm)" },
            label: { type: "string", description: "Optional label for this scenario" },
          },
          required: ["date", "start_time", "end_time"],
          description: "Single hypothetical shift to calculate",
        },
        compare: {
          type: "array",
          items: {
            type: "object",
            properties: {
              date: { type: "string", description: "Date (YYYY-MM-DD)" },
              start_time: { type: "string", description: "Start time (HH:mm)" },
              end_time: { type: "string", description: "End time (HH:mm)" },
              label: { type: "string", description: "Optional label for this scenario" },
            },
            required: ["date", "start_time", "end_time"],
          },
          minItems: 2,
          maxItems: 5,
          description: "Multiple scenarios to compare",
        },
        hypothetical_change: {
          type: "object",
          properties: {
            shift_id: { type: "string", description: "Shift ID from query_shifts (e.g. 'a1b2c' or 'virtual-a1b2c-2025-12-03')" },
            changes: {
              type: "object",
              properties: {
                start_time: { type: "string", description: "New start time (HH:mm)" },
                end_time: { type: "string", description: "New end time (HH:mm)" },
                date: { type: "string", description: "New date (YYYY-MM-DD)" },
              },
              description: "Changes to apply to the shift",
            },
          },
          required: ["shift_id", "changes"],
          description: "What-if modification to existing shift",
        },
      },
    },
    input_examples: [
      // "How much would I earn working 15-23 on Monday Jan 20?"
      {
        hypothetical: {
          date: "2025-01-20",
          start_time: "15:00",
          end_time: "23:00",
        },
      },
      // "Would I earn more working 12-18 or 16-22 on Friday?"
      {
        compare: [
          { date: "2025-01-24", start_time: "12:00", end_time: "18:00", label: "Day shift" },
          { date: "2025-01-24", start_time: "16:00", end_time: "22:00", label: "Evening shift" },
        ],
      },
      // "What if I worked Saturday vs Sunday same hours?"
      {
        compare: [
          { date: "2025-01-25", start_time: "10:00", end_time: "18:00", label: "Saturday" },
          { date: "2025-01-26", start_time: "10:00", end_time: "18:00", label: "Sunday" },
        ],
      },
      // "How much more would I earn if my shift started at 15 instead?"
      {
        hypothetical_change: {
          shift_id: "a1b2c",
          changes: { start_time: "15:00" },
        },
      },
      // "What if my recurring Monday shift ended at 22 instead of 20?"
      {
        hypothetical_change: {
          shift_id: "virtual-b3c4d-2025-01-20",
          changes: { end_time: "22:00" },
        },
      },
    ],
  },

  // ---------------------------------------------------------------------------
  // WORKPLACES
  // ---------------------------------------------------------------------------
  {
    name: "list_workplaces",
    description: `List workplaces (jobs) configured by the user.

By default, returns both active and archived workplaces.
Set includeArchived=false to return active workplaces only.

Returns each workplace with:
- id (UUID)
- name
- color
- isDefault
- isArchived
- archivedAt

Use this tool when:
- The user asks about their workplaces or jobs
- You need a jobId to filter shifts/wages by workplace
- You need to know which workplace is the default
- You need to find archived workplaces before restoring them
- Before creating a shift for a specific workplace

Note: Use the returned id (UUID) as jobId in query_shifts, calculate_wages, get_statistics, and manage_shift.`,
    input_schema: {
      type: "object",
      properties: {
        includeArchived: {
          type: "boolean",
          description: "Include archived workplaces in the result. Default: true",
        },
      },
    },
    input_examples: [
      // List active + archived workplaces (default)
      {},
      // List active workplaces only
      { includeArchived: false },
    ],
  },

  {
    name: "manage_workplace",
    description: `Create, update, set default, archive, unarchive, or delete workplaces (jobs).

Actions:
- CREATE: action="create", name/payrollDay/monthlyGoal are required; optional color/halfTaxMonth
- UPDATE: action="update", jobId (required), plus one or more fields to change
- SET DEFAULT: action="set_default", jobId (required)
- ARCHIVE: action="archive", jobId (required)
- UNARCHIVE: action="unarchive", jobId (required)
- DELETE: action="delete", jobId (required)

Important:
- To target an existing workplace, first call list_workplaces to get the jobId (UUID)
- Archived workplaces cannot be used for new shifts until unarchived
- Default workplaces cannot be archived or deleted
- Last active workplace cannot be archived or deleted
- After CREATE, offer to set up an initial wage snapshot for the new workplace (manage_wage_snapshots with action="create", jobId, from_date=null)`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["create", "update", "set_default", "archive", "unarchive", "delete"],
          description: "The operation to perform",
        },
        jobId: {
          type: "string",
          description: "Workplace/job UUID. Required for update, set_default, archive, unarchive, and delete",
        },
        name: {
          type: "string",
          description: "Workplace name (1-100 chars). Required for create",
        },
        color: {
          type: ["string", "null"],
          description: "Hex color like #22C55E, or null to clear",
        },
        payrollDay: {
          type: "integer",
          description: "Payroll day of month (1-31). Required for create.",
        },
        halfTaxMonth: {
          type: ["integer", "null"],
          description: "Half-tax month (11 or 12), or null to disable",
        },
        monthlyGoal: {
          type: ["integer", "null"],
          description: "Monthly goal amount (integer) or null. Required for create.",
        },
      },
      required: ["action"],
    },
    input_examples: [
      {
        action: "create",
        name: "Cafe Nord",
        color: "#22C55E",
        payrollDay: 15,
        monthlyGoal: null,
      },
      {
        action: "update",
        jobId: "2d6bb2fa-7fe9-4f62-b5ce-fb5b8620f809",
        name: "Cafe Nord AS",
      },
      {
        action: "set_default",
        jobId: "2d6bb2fa-7fe9-4f62-b5ce-fb5b8620f809",
      },
      {
        action: "archive",
        jobId: "2d6bb2fa-7fe9-4f62-b5ce-fb5b8620f809",
      },
      {
        action: "unarchive",
        jobId: "2d6bb2fa-7fe9-4f62-b5ce-fb5b8620f809",
      },
      {
        action: "delete",
        jobId: "2d6bb2fa-7fe9-4f62-b5ce-fb5b8620f809",
      },
    ],
  },

  // ---------------------------------------------------------------------------
  // FRIENDS & SHARING
  // ---------------------------------------------------------------------------
  {
    name: "list_friends",
    description: `List friends and sharing relationship status in both directions.

Each friend includes:
- id, name, email, phone
- sharesWithMe: if they share shifts with me
- blocked/showEarningsToMe: fields from sharer relation (or null)
- iShareWith: if I share shifts with them
- Note: blocked=true is treated as hidden-from-list state, not access denial for Wagey queries

Use includeBlocked=false to show only non-hidden sharers.`,
    input_schema: {
      type: "object",
      properties: {
        includeBlocked: {
          type: "boolean",
          description: "Include blocked/hidden sharers in results. Default: true",
        },
      },
    },
    input_examples: [{}, { includeBlocked: false }],
  },

  {
    name: "manage_friend_sharing",
    description: `Manage sharing relationships with friends.

Actions:
- share_by_identifier: identifier (email/phone), optional showEarnings
- share_back: friendId
- remove_recipient: friendId
- toggle_recipient_earnings: friendId, showEarnings
- block_sharer: friendId
- unblock_sharer: friendId
- set_sharer_muted: friendId, muted
- remove_sharer: friendId

Direction guardrails:
- Recipient actions require iShareWith=true
- Sharer actions require sharesWithMe=true`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: [
            "share_by_identifier",
            "share_back",
            "remove_recipient",
            "toggle_recipient_earnings",
            "block_sharer",
            "unblock_sharer",
            "set_sharer_muted",
            "remove_sharer",
          ],
          description: "The operation to perform",
        },
        identifier: {
          type: "string",
          description: "Email or phone number for share_by_identifier",
        },
        friendId: {
          type: "string",
          description: "Friend user ID (UUID)",
        },
        showEarnings: {
          type: "boolean",
          description: "Whether earnings are visible to recipient",
        },
        muted: {
          type: "boolean",
          description: "Mute notifications from this sharer",
        },
      },
      required: ["action"],
    },
    input_examples: [
      { action: "share_by_identifier", identifier: "friend@example.com", showEarnings: false },
      { action: "share_back", friendId: "2d6bb2fa-7fe9-4f62-b5ce-fb5b8620f809" },
      { action: "toggle_recipient_earnings", friendId: "2d6bb2fa-7fe9-4f62-b5ce-fb5b8620f809", showEarnings: true },
    ],
  },

  {
    name: "query_friend_shifts",
    description: `Query shifts from a friend who shares with me.

Access rules:
- Friend must have sharesWithMe=true from list_friends
- If blocked or no access, returns explicit no-access result

Filters match query_shifts:
- startDate/endDate (default current week)
- minTime/maxTime
- weekdays (0=Sun..6=Sat)
- sortBy:
  - date_latest (default): newest first
  - date_earliest: oldest first
  - earnings: highest first
  - hours: highest first
  - date: legacy alias for date_latest
- jobId (friend workplace UUID)
- limit (default 30, max 100)

Important:
- Use null for optional filters you are not using
- Never send empty strings for startDate, endDate, minTime, maxTime, or jobId`,
    input_schema: {
      type: "object",
      properties: {
        friendId: {
          type: "string",
          description: "Friend user ID (UUID) that shares shifts with me",
        },
        startDate: {
          type: "string",
          description: "Start date (YYYY-MM-DD)",
        },
        endDate: {
          type: "string",
          description: "End date (YYYY-MM-DD)",
        },
        limit: {
          type: "integer",
          description: "Max shifts to return (default 30, max 100)",
        },
        minTime: {
          type: "string",
          description: "Only shifts starting at or after this time (HH:mm). Use null if no lower time filter is needed; never send an empty string.",
        },
        maxTime: {
          type: "string",
          description: "Only shifts starting at or before this time (HH:mm). Use null if no upper time filter is needed; never send an empty string.",
        },
        weekdays: {
          type: "array",
          items: { type: "integer" },
          description: "Filter by weekday (0=Sun..6=Sat)",
        },
        sortBy: {
          type: "string",
          enum: ["date_latest", "date_earliest", "date", "earnings", "hours"],
          description: "Sort order (default: date_latest; date is a legacy alias for date_latest)",
        },
        jobId: {
          type: "string",
          description: "Filter to a specific workplace/job of the friend",
        },
      },
      required: ["friendId"],
    },
    input_examples: [
      { friendId: "2d6bb2fa-7fe9-4f62-b5ce-fb5b8620f809" },
      { friendId: "2d6bb2fa-7fe9-4f62-b5ce-fb5b8620f809", startDate: "2026-03-01", endDate: "2026-03-31", sortBy: "hours" },
    ],
  },

  // ---------------------------------------------------------------------------
  // ADVANCED SHIFT OPERATIONS
  // ---------------------------------------------------------------------------
  {
    name: "query_friend_featured_shift",
    description: `Get the featured shift preview for a friend (active > upcoming > past), using the same logic as the friends page.

Access rules:
- Friend must have sharesWithMe=true from list_friends
- If blocked or no access, returns explicit no-access/blocked result

Returns:
- friend info
- status: active, upcoming, past, or null
- showEarningsToMe
- featuredShift (or null)`,
    input_schema: {
      type: "object",
      properties: {
        friendId: {
          type: "string",
          description: "Friend user ID (UUID) that shares shifts with me",
        },
      },
      required: ["friendId"],
    },
    input_examples: [
      { friendId: "2d6bb2fa-7fe9-4f62-b5ce-fb5b8620f809" },
    ],
  },

  {
    name: "manage_shift_advanced",
    description: `Advanced shift mutations.

Actions:
- copy_shifts: shiftIds[], targetDate
- update_custom_supplements: shiftId, customSupplements, optional recurringId+shiftDate
- convert_recurring_to_standalone: recurringId, shiftDate, startTime, endTime
- move_recurring_occurrence: recurringId, sourceDate, targetDate, startTime, endTime
- clear_shift_snapshots: shiftId`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: [
            "copy_shifts",
            "update_custom_supplements",
            "convert_recurring_to_standalone",
            "move_recurring_occurrence",
            "clear_shift_snapshots",
          ],
          description: "The operation to perform",
        },
        shiftIds: {
          type: "array",
          items: { type: "string" },
          description: "Shift IDs for copy_shifts",
        },
        targetDate: {
          type: "string",
          description: "Target date (YYYY-MM-DD) for copy/move",
        },
        shiftId: {
          type: "string",
          description: "Shift ID for update_custom_supplements or clear_shift_snapshots",
        },
        customSupplements: {
          type: ["object", "null"],
          description: "Custom supplements payload or null to clear",
        },
        recurringId: {
          type: "string",
          description: "Recurring shift ID for recurring actions",
        },
        shiftDate: {
          type: "string",
          description: "Shift date (YYYY-MM-DD) for recurring conversion",
        },
        sourceDate: {
          type: "string",
          description: "Source date (YYYY-MM-DD) for move_recurring_occurrence",
        },
        startTime: {
          type: "string",
          description: "Start time HH:mm",
        },
        endTime: {
          type: "string",
          description: "End time HH:mm",
        },
      },
      required: ["action"],
    },
    input_examples: [
      { action: "copy_shifts", shiftIds: ["a1b2c"], targetDate: "2026-03-10" },
      { action: "clear_shift_snapshots", shiftId: "a1b2c" },
    ],
  },

  // ---------------------------------------------------------------------------
  // FEEDBACK & PROFILE
  // ---------------------------------------------------------------------------
  {
    name: "manage_feedback",
    description: `Submit new feedback or list your previous feedback.

Actions:
- submit: message
- list: no additional parameters`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["submit", "list"],
          description: "The operation to perform",
        },
        message: {
          type: "string",
          description: "Feedback message for submit action",
        },
      },
      required: ["action"],
    },
    input_examples: [{ action: "submit", message: "Would love better weekend filters in stats." }, { action: "list" }],
  },

  {
    name: "manage_profile",
    description: `View profile basics or update first name.

Actions:
- view: returns low-risk profile fields (id, name, email, phone)
- update_name: firstName`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["view", "update_name"],
          description: "The operation to perform",
        },
        firstName: {
          type: "string",
          description: "New first name for update_name",
        },
      },
      required: ["action"],
    },
    input_examples: [{ action: "view" }, { action: "update_name", firstName: "Hjalmar" }],
  },
];

/**
 * Tool name type
 */
export type ToolName =
  | "manage_shift"
  | "query_shifts"
  | "calculate_wages"
  | "draft_recurring_shift"
  | "confirm_recurring_shift"
  | "manage_recurring_shift"
  | "manage_recurring_exclusion"
  | "get_statistics"
  | "manage_settings"
  | "manage_workplace"
  | "get_wage_info"
  | "manage_wage_snapshots"
  | "calculate_earnings"
  | "list_workplaces"
  | "list_friends"
  | "manage_friend_sharing"
  | "query_friend_shifts"
  | "query_friend_featured_shift"
  | "manage_shift_advanced"
  | "manage_feedback"
  | "manage_profile";

/**
 * Tool result type
 */
export type ToolResult = {
  success: boolean;
  message: string;
  data?: unknown;
  summary?: {
    shiftCount: number;
    totalHours: number;
    totalGross: number;
    totalNet: number;
    avgHoursPerShift: number;
    avgGrossPerShift: number;
  };
  currency?: string; // User's selected currency for earnings data
};
