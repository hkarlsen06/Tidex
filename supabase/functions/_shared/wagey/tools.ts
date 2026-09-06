/**
 * Wagey Chat Tools
 *
 * Tool definitions for AI agent to manage shifts.
 * input_examples are preserved and folded into OpenAI tool descriptions at runtime.
 */

import { z } from "zod";
import type { FunctionTool } from "./ai-types.ts";
import type { HHMM } from "./payroll/types.ts";

// =============================================================================
// ZOD SCHEMAS (for validation in executor)
// =============================================================================

/**
 * Short ID schema - accepts 4-8 hex chars (short ID) or full UUID
 */
const shortOrFullId = z.string().regex(
  /^[a-f0-9]{4,8}$|^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i,
);
const optionalFilterPlaceholders = new Set([
  "",
  "null",
  "none",
  "undefined",
  "n/a",
  "all",
  "any",
]);

function normalizeOptionalFilter(value: unknown): unknown {
  if (value === null) return undefined;
  if (typeof value !== "string") return value;
  const trimmed = value.trim();
  return optionalFilterPlaceholders.has(trimmed.toLowerCase())
    ? undefined
    : trimmed;
}

const optionalDateFilter = z.preprocess(
  normalizeOptionalFilter,
  z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
);
const optionalTimeFilter = z.preprocess(
  normalizeOptionalFilter,
  z.string().regex(/^\d{2}:\d{2}$/).optional(),
);
const optionalUuidFilter = z.preprocess(
  normalizeOptionalFilter,
  z.string().uuid().optional(),
);

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
  startDate: optionalDateFilter,
  endDate: optionalDateFilter,
  limit: z.number().int().min(1).max(100).optional().default(30),
  minTime: optionalTimeFilter,
  maxTime: optionalTimeFilter,
  weekdays: z.array(z.number().int().min(0).max(6)).optional(),
  sortBy: z
    .enum([
      "date_latest",
      "date_earliest",
      "date",
      "day",
      "start",
      "end",
      "hours",
      "earnings",
      "gross",
      "net",
      "workplace",
      "id",
    ])
    .optional()
    .default("date_latest"),
  sortDirection: z.enum(["asc", "desc"]).optional(),
  // Optional workplace/job filter (full UUID from list_workplaces)
  jobId: optionalUuidFilter,
});

export type QueryShiftsInput = z.infer<typeof queryShiftsSchema>;

/**
 * Query Events Tool Schema
 */
export const queryEventsSchema = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  limit: z.number().int().min(1).max(100).optional().default(30),
  kind: z.enum(["all", "timed", "all_day"]).optional().default("all"),
  sortBy: z.enum(["start_earliest", "start_latest"]).optional().default(
    "start_earliest",
  ),
});

export type QueryEventsInput = z.infer<typeof queryEventsSchema>;

/**
 * Manage Event Tool Schema
 */
const eventTimeSchema = z.string().regex(/^\d{2}:\d{2}$|^24:00$/);
const reminderAnchorTimeSchema = z.string().regex(/^\d{2}:\d{2}$/);
const hhmmSchema = eventTimeSchema.transform((value) => value as HHMM);
const pauseWindowSchema = z.object({
  start: hhmmSchema,
  end: hhmmSchema,
})
  .strict()
  .refine((window) => window.start !== window.end, {
    message: "Pause windows require different start and end times",
  });
const customPauseWindowsSchema = z.object({
  windows: z.array(pauseWindowSchema).min(1),
}).strict();

export const manageEventSchema = z.object({
  action: z.enum(["create", "update", "delete"]),
  eventId: shortOrFullId.optional(),
  note: z.string().min(1).optional(),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  isAllDay: z.boolean().optional(),
  startTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  endTime: eventTimeSchema.optional(),
  notificationMinutesArray: z.array(z.number().int().min(0)).max(10).optional(),
  notificationAnchorTime: reminderAnchorTimeSchema.nullable().optional(),
});

export type ManageEventInput = z.infer<typeof manageEventSchema>;

/**
 * Plan Schedule Tool Schema
 */
export const planScheduleSchema = z.object({
  action: z.enum(["agenda", "conflicts", "free_slots"]),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  includeShifts: z.boolean().optional().default(true),
  includeEvents: z.boolean().optional().default(true),
  isAllDay: z.boolean().optional(),
  startTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  endTime: eventTimeSchema.optional(),
  excludeEventId: shortOrFullId.optional(),
  durationMinutes: z.number().int().min(1).max(1440).optional(),
  windowStart: z.string().regex(/^\d{2}:\d{2}$/).optional().default("00:00"),
  windowEnd: eventTimeSchema.optional().default("24:00"),
});

export type PlanScheduleInput = z.infer<typeof planScheduleSchema>;

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
  jobId: z.string().uuid().optional(),
  frequency: z.enum(["weekly", "biweekly", "every_3_weeks", "every_4_weeks"]),
  endType: z.enum(["never", "after_months", "after_years", "on_date"]),
  endValue: z.union([
    z.number().int().min(1),
    z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  ]).optional(),
});

export type DraftRecurringShiftInput = z.infer<
  typeof draftRecurringShiftSchema
>;

/**
 * Confirm Recurring Shift Tool Schema (Step 2 of 2)
 * Supports multiple weekdays in a single recurring shift (e.g., Mon/Wed/Fri)
 */
export const confirmRecurringShiftSchema = z.object({
  weekdays: z.array(weekdayAnchorSchema).min(1).max(7),
  start: z.string().regex(/^\d{2}:\d{2}$/),
  end: z.string().regex(/^\d{2}:\d{2}$/),
  jobId: z.string().uuid().optional(),
  frequency: z.enum(["weekly", "biweekly", "every_3_weeks", "every_4_weeks"]),
  endType: z.enum(["never", "after_months", "after_years", "on_date"]),
  endValue: z.union([
    z.number().int().min(1),
    z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  ]).optional(),
  conflictResolution: z.enum(["keep_both", "skip_conflicts"]),
});

export type ConfirmRecurringShiftInput = z.infer<
  typeof confirmRecurringShiftSchema
>;

/**
 * Manage Recurring Shift Tool Schema
 */
export const manageRecurringShiftSchema = z.object({
  action: z.enum([
    "draft_create",
    "confirm_create",
    "list",
    "update",
    "delete",
    "add_exclusion",
    "remove_exclusion",
  ]),
  recurringId: shortOrFullId.optional(),
  // Create/update fields - use weekdays array to replace all weekdays on update
  weekdays: z.array(weekdayAnchorSchema).min(1).max(7).optional(),
  start: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  end: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  jobId: z.string().uuid().optional(),
  frequency: z.enum(["weekly", "biweekly", "every_3_weeks", "every_4_weeks"])
    .optional(),
  endType: z.enum(["never", "after_months", "after_years", "on_date"])
    .optional(),
  endValue: z.union([
    z.number().int().min(1),
    z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  ]).optional(),
  conflictResolution: z.enum(["keep_both", "skip_conflicts"]).optional(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

export type ManageRecurringShiftInput = z.infer<
  typeof manageRecurringShiftSchema
>;

/**
 * Manage Account Tool Schema
 */
export const manageAccountSchema = z.object({
  action: z.enum([
    "view_settings",
    "update_settings",
    "view_profile",
    "update_name",
    "submit_feedback",
    "list_feedback",
  ]),
  category: z.enum(["display", "tax", "goals", "preferences"]).optional(),
  settings: z.record(z.string(), z.any()).optional(),
  firstName: z.string().max(100).optional(),
  message: z.string().optional(),
});

export type ManageAccountInput = z.infer<typeof manageAccountSchema>;

/**
 * Manage Recurring Exclusion Tool Schema
 */
export const manageRecurringExclusionSchema = z.object({
  recurringId: shortOrFullId,
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  action: z.enum(["add", "remove"]),
});

export type ManageRecurringExclusionInput = z.infer<
  typeof manageRecurringExclusionSchema
>;

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
    "shift_gaps",
  ]),
  year: z.number().int().min(2020).max(2100).optional(),
  month: z.number().int().min(1).max(12).optional(),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  limit: z.number().int().min(1).max(50).optional().default(10),
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

export type ManageFriendSharingInput = z.infer<
  typeof manageFriendSharingSchema
>;

/**
 * Query Friend Shifts Tool Schema
 */
export const queryFriendShiftsSchema = z.object({
  mode: z.enum(["shifts", "featured"]).optional().default("shifts"),
  friendId: z.string().uuid(),
  startDate: optionalDateFilter,
  endDate: optionalDateFilter,
  limit: z.number().int().min(1).max(100).optional().default(30),
  minTime: optionalTimeFilter,
  maxTime: optionalTimeFilter,
  weekdays: z.array(z.number().int().min(0).max(6)).optional(),
  sortBy: z
    .enum([
      "date_latest",
      "date_earliest",
      "date",
      "day",
      "start",
      "end",
      "hours",
      "earnings",
      "gross",
      "net",
      "workplace",
      "id",
    ])
    .optional()
    .default("date_latest"),
  sortDirection: z.enum(["asc", "desc"]).optional(),
  jobId: optionalUuidFilter,
});

export type QueryFriendShiftsInput = z.infer<typeof queryFriendShiftsSchema>;

/**
 * Query Friend Featured Shift Tool Schema
 * Reuses the same featured-shift preview logic as sharing UI.
 */
export const queryFriendFeaturedShiftSchema = z.object({
  friendId: z.string().uuid(),
});

export type QueryFriendFeaturedShiftInput = z.infer<
  typeof queryFriendFeaturedShiftSchema
>;

/**
 * Manage Shift Advanced Tool Schema
 */
export const manageShiftAdvancedSchema = z.object({
  action: z.enum([
    "copy_shifts",
    "update_custom_pause_windows",
    "update_custom_supplements",
    "convert_recurring_to_standalone",
    "move_recurring_occurrence",
    "clear_shift_snapshots",
  ]),
  shiftIds: z.array(z.string().min(1)).min(1).optional(),
  targetDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  shiftId: z.string().min(1).optional(),
  customPauseWindows: z.union([customPauseWindowsSchema, z.null()]).optional(),
  customSupplements: z.any().optional(),
  recurringId: shortOrFullId.optional(),
  shiftDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  startTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  endTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  sourceDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

export type ManageShiftAdvancedInput = z.infer<
  typeof manageShiftAdvancedSchema
>;

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

const overtimeTimeSchema = z.string().regex(
  /^(?:[01]\d|2[0-3]):[0-5]\d|24:00$/,
);

const overtimeRuleSchema = z.object({
  days: z.array(z.number().int().min(1).max(7)).min(1),
  appliesOnHolidays: z.boolean(),
  from: overtimeTimeSchema,
  to: overtimeTimeSchema,
  percent: z.number().positive(),
}).strict().refine((rule) => {
  const from = timeToMinutes(rule.from);
  const to = timeToMinutes(rule.to);
  return from != null && to != null && from < to && to <= 24 * 60;
}, {
  message: "Overtime rules require same-day ranges with from < to <= 24:00",
});

const overtimeConfigSchema = z.object({
  enabled: z.boolean(),
  weeklyThresholdHours: z.number().positive(),
  rules: z.array(overtimeRuleSchema),
}).strict().superRefine((config, ctx) => {
  if (!config.enabled) return;
  if (config.rules.length === 0) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "Enabled overtime requires at least one rule",
      path: ["rules"],
    });
    return;
  }
  if (!rulesCoverFullDay(config.rules, false)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message:
        "Overtime rules must cover 00:00-24:00 for every non-holiday day",
      path: ["rules"],
    });
  }
  if (!rulesCoverFullDay(config.rules, true)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message:
        "Overtime rules must cover 00:00-24:00 for Norwegian public holidays",
      path: ["rules"],
    });
  }
});

function timeToMinutes(value: string): number | null {
  const match = /^(\d{2}):(\d{2})$/.exec(value);
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (minutes < 0 || minutes >= 60 || hours < 0 || hours > 24) return null;
  if (hours === 24 && minutes !== 0) return null;
  return hours * 60 + minutes;
}

function rulesCoverFullDay(
  rules: Array<z.infer<typeof overtimeRuleSchema>>,
  holiday: boolean,
): boolean {
  for (let day = 1; day <= 7; day++) {
    const intervals = rules
      .filter((rule) =>
        rule.days.includes(day) &&
        (holiday ? rule.appliesOnHolidays : !isHolidayOnlyRule(rule))
      )
      .map((rule) =>
        [timeToMinutes(rule.from), timeToMinutes(rule.to)] as const
      )
      .filter((interval): interval is readonly [number, number] =>
        interval[0] != null && interval[1] != null
      );
    if (!intervalsCoverFullDay(intervals)) return false;
  }
  return true;
}

function intervalsCoverFullDay(
  intervals: readonly (readonly [number, number])[],
): boolean {
  let coveredUntil = 0;
  for (const [from, to] of [...intervals].sort((a, b) => a[0] - b[0])) {
    if (from > coveredUntil) return false;
    coveredUntil = Math.max(coveredUntil, to);
    if (coveredUntil >= 24 * 60) return true;
  }
  return false;
}

function isHolidayOnlyRule(
  rule: Pick<z.infer<typeof overtimeRuleSchema>, "days" | "appliesOnHolidays">,
): boolean {
  return rule.appliesOnHolidays && rule.days.length === 7 &&
    new Set(rule.days).size === 7;
}

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
  from_date: z.union([z.string().regex(/^\d{4}-\d{2}-\d{2}$/), z.null()])
    .optional(),
  // Wage settings - all optional for update (only include fields to change)
  hourly_wage: z.number().positive().optional(),
  wage_level: z.number().int().min(1).max(9).nullable().optional(),
  // Tax settings
  tax_enabled: z.boolean().optional(),
  tax_percentage: z.number().min(0).max(100).optional(),
  // Break deduction settings
  break_enabled: z.boolean().optional(),
  break_method: z.enum(["proportional", "base_only", "end_of_shift", "none"])
    .optional(),
  break_threshold_hours: z.number().positive().optional(),
  break_deduction_minutes: z.number().int().min(0).optional(),
  // Supplements - "copy_current" copies from current snapshot, or provide array of rules
  supplements: z.union([
    z.literal("copy_current"),
    z.array(z.union([supplementRuleSchema, supplementRuleAliasSchema])),
  ]).optional(),
  overtime: overtimeConfigSchema.optional(),
});

export type ManageWageSnapshotsInput = z.infer<
  typeof manageWageSnapshotsSchema
>;

/**
 * Manage Payroll Adjustment Tool Schema
 *
 * The advertised OpenAI schema is strict and required-nullable. The runtime
 * parser remains tolerant so old conversation history or non-strict tool calls
 * can still be validated with action-specific errors by the executor.
 */
export const managePayrollAdjustmentSchema = z.object({
  action: z.enum(["list", "create", "update", "delete"]),
  adjustmentId: shortOrFullId.nullable().optional(),
  payoutStart: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  payoutEnd: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  payoutDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  payoutMonth: z.string().regex(/^\d{4}-\d{2}$/).nullable().optional(),
  jobId: z.string().uuid().nullable().optional(),
  amount: z.number().nullable().optional(),
  currency: z.string().min(1).max(12).nullable().optional(),
  category: z.enum(["retro_pay", "bonus", "correction", "other"]).nullable()
    .optional(),
  taxTreatment: z.enum([
    "gross_taxable",
    "net_manual",
    "excluded_from_tax_estimate",
  ]).nullable().optional(),
  description: z.string().min(1).max(240).nullable().optional(),
  note: z.string().max(1000).nullable().optional(),
  earnedFromDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable()
    .optional(),
  earnedToDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  clearFields: z.array(z.enum([
    "jobId",
    "note",
    "earnedFromDate",
    "earnedToDate",
  ])).nullable().optional(),
  limit: z.number().int().min(1).max(100).nullable().optional(),
}).strict();

export type ManagePayrollAdjustmentInput = z.infer<
  typeof managePayrollAdjustmentSchema
>;

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
    shift_id: z.string().regex(
      /^[a-f0-9]{4,8}$|^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$|^virtual-[a-f0-9]{5}-\d{4}-\d{2}-\d{2}$/i,
    ),
    changes: z.object({
      start_time: z.string().regex(/^\d{2}:\d{2}$/).optional(),
      end_time: z.string().regex(/^\d{2}:\d{2}$/).optional(),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    }),
  }).optional(),
}).refine(
  (data) => {
    // Exactly one mode must be specified
    const modes = [data.hypothetical, data.compare, data.hypothetical_change]
      .filter(Boolean);
    return modes.length === 1;
  },
  {
    message:
      "Exactly one mode must be specified: hypothetical, compare, or hypothetical_change",
  },
);

export type CalculateEarningsInput = z.infer<typeof calculateEarningsSchema>;

// =============================================================================
// TOOL DEFINITIONS
// =============================================================================

const allTools: FunctionTool[] = [
  // ---------------------------------------------------------------------------
  // SHIFT MANAGEMENT
  // ---------------------------------------------------------------------------
  {
    name: "manage_shift",
    description:
      `Create identical shifts on one or more dates, update one shift, or delete one/multiple shifts. Create requires dates/start/end; update requires shiftId and changed start/end/date; delete requires shiftId or shiftIds. Query IDs before update/delete. End before start means overnight. Resolve named jobs with list_workplaces; omitted jobId uses the default. Creation requires the selected/default job's paySetupStatus="configured" (baseline wage snapshot).`,
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
          description:
            "Dates for new shifts (YYYY-MM-DD format). Only for create.",
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
          description:
            "Job UUID from list_workplaces. Only for create. Omit to use the default configured job.",
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
  },

  {
    name: "query_shifts",
    description:
      `Get itemized shifts and IDs for updates/deletes. Defaults to the current week; for all-time queries use 2000-01-01 through today's local date. Use get_statistics for aggregate summaries.
Returns data (id, date, day, start, end, hours, gross, net if tax enabled, workplace), summary totals/averages, and currency. Omitted jobId includes all jobs.
minTime/maxTime filter shift start time. date_latest (default) sorts newest first, date_earliest oldest; date aliases date_latest. For extrema, set the relevant sortBy and explicit sortDirection before limit (hours+asc shortest, hours+desc longest, gross+desc highest pay). Use null for unused filters, never empty strings.`,
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
          description:
            "Only shifts starting at or after this time (HH:mm). Use null if no lower time filter is needed; never send an empty string.",
        },
        maxTime: {
          type: "string",
          description:
            "Only shifts starting at or before this time (HH:mm). Use null if no upper time filter is needed; never send an empty string.",
        },
        weekdays: {
          type: "array",
          items: { type: "integer" },
          description:
            "Filter by weekday (see weekday_reference in system prompt)",
        },
        sortBy: {
          type: "string",
          enum: [
            "date_latest",
            "date_earliest",
            "date",
            "day",
            "start",
            "end",
            "hours",
            "earnings",
            "gross",
            "net",
            "workplace",
            "id",
          ],
          description:
            "Column to sort by (default: date_latest; date is a legacy alias for date_latest; earnings is an alias for gross)",
        },
        sortDirection: {
          type: "string",
          enum: ["asc", "desc"],
          description:
            "Optional sort direction. Use asc for shortest/lowest/earliest and desc for longest/highest/latest. Legacy defaults: date_latest/date desc, date_earliest asc, hours/earnings desc.",
        },
        jobId: {
          type: "string",
          description:
            "Filter to a specific workplace/job (UUID from list_workplaces)",
        },
      },
    },
  },

  {
    name: "query_events",
    description:
      `Find private calendar events and IDs before update/delete. Filters by date overlap; defaults to the current week. Returns id, note, startDate/endDate, isAllDay, startTime/endTime, reminderMinutes, and reminderAnchorTime. Use plan_schedule for a merged shift/event agenda.`,
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
          description: "Max events to return (default 30, max 100)",
        },
        kind: {
          type: "string",
          enum: ["all", "timed", "all_day"],
          description:
            "Filter to all events, only timed events, or only all-day events",
        },
        sortBy: {
          type: "string",
          enum: ["start_earliest", "start_latest"],
          description: "Sort order (default: start_earliest)",
        },
      },
    },
  },

  {
    name: "manage_event",
    description:
      `Create, update, or delete private calendar events. Create requires note, startDate/endDate, isAllDay; timed events also require startTime/endTime and must stay on one date. All-day events may span dates and must omit times. Their reminders use notificationAnchorTime; timed reminders use event start. Update/delete require eventId from query_events; update includes only changed fields.`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["create", "update", "delete"],
          description: "The operation to perform",
        },
        eventId: {
          type: "string",
          description: "Event ID for update/delete",
        },
        note: {
          type: "string",
          description: "Event note/title",
        },
        startDate: {
          type: "string",
          description: "Start date (YYYY-MM-DD)",
        },
        endDate: {
          type: "string",
          description: "End date (YYYY-MM-DD)",
        },
        isAllDay: {
          type: "boolean",
          description: "Whether the event is all day",
        },
        startTime: {
          type: "string",
          description: "Start time (HH:mm). Timed events only.",
        },
        endTime: {
          type: "string",
          description: "End time (HH:mm or 24:00). Timed events only.",
        },
        notificationMinutesArray: {
          type: "array",
          items: { type: "integer" },
          description: "Reminder offsets in minutes before the event",
        },
        notificationAnchorTime: {
          type: ["string", "null"],
          description: "Reminder anchor time (HH:mm) for all-day events",
        },
      },
      required: ["action"],
    },
    input_examples: [
      {
        "action": "create",
        "note": "Easter holiday",
        "startDate": "2026-04-17",
        "endDate": "2026-04-20",
        "isAllDay": true,
        "notificationMinutesArray": [
          120,
        ],
        "notificationAnchorTime": "09:00",
      },
    ],
  },

  {
    name: "plan_schedule",
    description:
      `Read-only planning across shifts and private events: agenda returns chronological entries; conflicts checks a candidate event for overlaps (excludeEventId ignores the edited event); free_slots finds openings of durationMinutes within windowStart/windowEnd. Does not create or reserve events.`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["agenda", "conflicts", "free_slots"],
          description: "Planning action to perform",
        },
        startDate: {
          type: "string",
          description: "Start date (YYYY-MM-DD)",
        },
        endDate: {
          type: "string",
          description: "End date (YYYY-MM-DD)",
        },
        includeShifts: {
          type: "boolean",
          description:
            "Include shifts in agenda/conflict/free-slot calculations (default true)",
        },
        includeEvents: {
          type: "boolean",
          description:
            "Include private events in agenda/conflict/free-slot calculations (default true)",
        },
        isAllDay: {
          type: "boolean",
          description: "Candidate event shape for conflicts",
        },
        startTime: {
          type: "string",
          description: "Candidate start time (HH:mm) for conflicts",
        },
        endTime: {
          type: "string",
          description: "Candidate end time (HH:mm or 24:00) for conflicts",
        },
        excludeEventId: {
          type: "string",
          description: "Existing event ID to ignore during conflict checks",
        },
        durationMinutes: {
          type: "integer",
          description:
            "Required for free_slots. Minimum free-slot length in minutes.",
        },
        windowStart: {
          type: "string",
          description:
            "Daily search window start for free_slots (default 00:00)",
        },
        windowEnd: {
          type: "string",
          description: "Daily search window end for free_slots (default 24:00)",
        },
      },
      required: ["action", "startDate", "endDate"],
    },
    input_examples: [
      {
        "action": "free_slots",
        "startDate": "2026-04-15",
        "endDate": "2026-04-17",
        "durationMinutes": 90,
        "windowStart": "08:00",
        "windowEnd": "20:00",
      },
    ],
  },

  {
    name: "calculate_wages",
    description:
      `Calculate wages for an earnings date range, optionally scoped to jobId. Returns gross/net (when tax configured), hours, tax, shift count, shift-only and adjustment-only totals, and payroll adjustments for the corresponding payout period.
For payout questions, pass the preceding full calendar month: payout in month M covers earnings in M-1. payoutStart/payoutEnd confirm the mapped payout period. June earnings include July payout adjustments, not June payout adjustments. Use get_statistics for common earnings summaries, never for payout questions.`,
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
          description:
            "Filter to a specific workplace/job (UUID from list_workplaces)",
        },
      },
      required: ["startDate", "endDate"],
    },
  },

  // ---------------------------------------------------------------------------
  // RECURRING SHIFTS (2-step: draft then confirm)
  // ---------------------------------------------------------------------------
  {
    name: "draft_recurring_shift",
    description:
      `Step 1 of 2: Preview a recurring shift pattern WITHOUT creating it.

Purpose: Validates the pattern and checks for conflicts with existing shifts before committing.

Required parameters:
- weekdays: Array of {day, anchorDate} objects. Day uses weekday numbers (see weekday_reference). anchorDate (YYYY-MM-DD) MUST fall on that weekday and determines which week the recurring shift starts from.
- start/end: Times in HH:mm format
- frequency: weekly, biweekly, every_3_weeks, or every_4_weeks
- endType: never, after_months, after_years, or on_date (with endValue)

Optional: jobId (UUID from list_workplaces). Omit to use the default configured job. The job must have paySetupStatus="configured" before recurring shifts can be created.

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
                description:
                  "Start date (YYYY-MM-DD). Must fall on the correct weekday. Determines which week THIS weekday starts from — each weekday can have a different anchor week to create alternating patterns.",
              },
            },
            required: ["day", "anchorDate"],
          },
          minItems: 1,
          maxItems: 7,
          description:
            "Array of weekdays with their anchor dates. Use multiple entries for multi-day patterns (same week: Mon/Wed/Fri; alternating weeks: offset anchorDates by one week).",
        },
        start: {
          type: "string",
          description: "Start time (HH:mm)",
        },
        end: {
          type: "string",
          description: "End time (HH:mm)",
        },
        jobId: {
          type: "string",
          description:
            "Job UUID from list_workplaces. Omit to use the default configured job.",
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
          description:
            "For after_months/after_years: number of months/years. For on_date: end date (YYYY-MM-DD).",
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
    description:
      `Step 2 of 2: Actually create the recurring shift after reviewing the draft.

IMPORTANT: Only call this AFTER draft_recurring_shift. Use identical parameters from the draft.

Required: All the same parameters from draft_recurring_shift, PLUS:
- conflictResolution: "keep_both" (recurring shift coexists with existing shifts) or "skip_conflicts" (recurring shift skips dates with existing shifts)

Use the same jobId from the draft when the user selected a specific job. The job must have paySetupStatus="configured".

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
                description:
                  "Start date (YYYY-MM-DD). Must fall on the correct weekday. Determines which week the recurring shift starts from.",
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
        jobId: {
          type: "string",
          description:
            "Same job UUID from draft. Omit to use the default configured job.",
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
          description:
            "keep_both: recurring shift coexists with conflicts. skip_conflicts: recurring shift skips dates with existing shifts.",
        },
      },
      required: [
        "weekdays",
        "start",
        "end",
        "frequency",
        "endType",
        "conflictResolution",
      ],
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
    description:
      `Manage recurring shifts: draft_create previews/validates and checks conflicts; confirm_create writes the same pattern/jobId with conflictResolution. Ask the user how to resolve conflicts when present. Creation requires paySetupStatus="configured".
Use ONE rule with multiple weekdays. Each anchorDate must match its weekday and intended starting week; offset anchors by a week for alternating biweekly/every_N_weeks patterns.
list returns IDs/patterns/schedules; list before update/delete/exclusions. update requires recurringId and changed fields; weekdays replaces the entire array. delete removes the rule and its virtual occurrences immediately; standalone/converted shifts remain. add_exclusion/remove_exclusion require recurringId/date to skip/restore an occurrence.`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: [
            "draft_create",
            "confirm_create",
            "list",
            "update",
            "delete",
            "add_exclusion",
            "remove_exclusion",
          ],
          description: "The operation to perform",
        },
        recurringId: {
          type: "string",
          description:
            "Recurring shift ID (required for update/delete/add_exclusion/remove_exclusion)",
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
                description:
                  "Start date (YYYY-MM-DD). Must fall on the correct weekday. Determines which week the recurring shift starts from.",
              },
            },
            required: ["day", "anchorDate"],
          },
          minItems: 1,
          maxItems: 7,
          description:
            "New weekdays for update (replaces all existing weekdays)",
        },
        start: {
          type: "string",
          description: "New start time for update",
        },
        end: {
          type: "string",
          description: "New end time for update",
        },
        jobId: {
          type: "string",
          description:
            "Job UUID from list_workplaces for draft_create/confirm_create. Omit to use the default configured job.",
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
          description:
            "For after_months/after_years: number of months/years. For on_date: end date (YYYY-MM-DD).",
        },
        conflictResolution: {
          type: "string",
          enum: ["keep_both", "skip_conflicts"],
          description:
            "Required for confirm_create. keep_both allows conflicts; skip_conflicts skips dates with existing shifts.",
        },
        date: {
          type: "string",
          description:
            "Occurrence date (YYYY-MM-DD) for add_exclusion/remove_exclusion.",
        },
      },
      required: ["action"],
    },
    input_examples: [
      {
        "action": "draft_create",
        "weekdays": [
          {
            "day": 1,
            "anchorDate": "2025-01-20",
          },
          {
            "day": 3,
            "anchorDate": "2025-01-22",
          },
          {
            "day": 5,
            "anchorDate": "2025-01-24",
          },
        ],
        "start": "09:00",
        "end": "17:00",
        "frequency": "weekly",
        "endType": "after_months",
        "endValue": 6,
      },
    ],
  },

  {
    name: "manage_recurring_exclusion",
    strict: true,
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
          description:
            "add: exclude the date. remove: restore previously excluded date.",
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
    description:
      `Precomputed earnings/hour/shift-count summaries; use instead of manual calculations. Use query_shifts only for itemized rows. For payouts use calculate_wages over the previous calendar month.
Metrics:
- current_month/last_month: earnings, hours, shift count for work in that month.
- year_to_date: Jan 1 through today's date; past years stop at the equivalent date for same-point comparisons.
- full_year: Jan 1–Dec 31 totals, including for past years.
- yearly_months: all 12 months with earnings, hours, shifts.
- this_week: Monday–Sunday daily breakdown.
- monthly_goal: goal progress.
- supplement_breakdown: base pay vs supplements.
- shift_gaps: longest breaks between consecutive shifts; use explicit startDate/endDate for custom periods and limit for number of gaps.
Optional year/month default to current; jobId scopes to a job.`,
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
            "shift_gaps",
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
        startDate: {
          type: "string",
          description:
            "Optional custom start date (YYYY-MM-DD), especially for shift_gaps.",
        },
        endDate: {
          type: "string",
          description:
            "Optional custom end date (YYYY-MM-DD), especially for shift_gaps.",
        },
        limit: {
          type: "integer",
          description:
            "For shift_gaps, number of longest gaps to return (default 10, max 50).",
        },
        jobId: {
          type: "string",
          description:
            "Filter to a specific workplace/job (UUID from list_workplaces)",
        },
      },
      required: ["metric"],
    },
  },

  // ---------------------------------------------------------------------------
  // SETTINGS
  // ---------------------------------------------------------------------------
  {
    name: "manage_account",
    description:
      `View or update account-level settings, profile basics, and feedback.

Use this for user preferences, monthly goals, currency/display settings, profile first name, and feedback.
Do NOT use this for wages, wage history, tax percentage, tariff setup, or pause/supplement history; use get_wage_info/manage_wage_snapshots for those.

Actions:
- view_settings: returns display, goals, preferences, and tax halfTaxMonth
- update_settings: category plus settings object
- view_profile: returns low-risk profile fields (id, name, email, phone)
- update_name: firstName
- submit_feedback: message
- list_feedback: returns previous feedback

Settings categories and keys:
- display: theme (light/dark), defaultShiftsView (calendar/list), currency (display symbol, default kr), showDashboardClockButtons (boolean, default true)
- tax: halfTaxMonth (1-12, global half-tax month override only)
- goals: monthlyGoal (baseline gross target), payrollDay (1-31), monthlyGoalsByMonth (overrides; unset months use baseline)
- preferences: defaultStartupTab (home/shifts/add/stats/sharing)

Only include changed settings. For monthlyGoalsByMonth, use { "YYYY-MM": amount } to set an override and null to remove it. view_settings returns all overrides and the current month's effective goal.`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: [
            "view_settings",
            "update_settings",
            "view_profile",
            "update_name",
            "submit_feedback",
            "list_feedback",
          ],
          description: "The account, settings, profile, or feedback operation.",
        },
        category: {
          type: "string",
          enum: ["display", "tax", "goals", "preferences"],
          description: "Required for update_settings.",
        },
        settings: {
          type: "object",
          description: "Key-value settings to update for update_settings.",
        },
        firstName: {
          type: "string",
          description: "New first name for update_name.",
        },
        message: {
          type: "string",
          description: "Feedback text for submit_feedback.",
        },
      },
      required: ["action"],
    },
    input_examples: [
      {
        "action": "update_settings",
        "category": "goals",
        "settings": {
          "monthlyGoal": 50000,
        },
      },
    ],
  },

  {
    name: "manage_settings",
    description:
      `View or update user settings (NOT wages - use get_wage_info for wage/tax/pause history).

Actions:
- VIEW: No parameters or action="view" - Returns display, goals, preferences, and tax (halfTaxMonth only)
- UPDATE: action="update", category, settings object with key-value pairs

Categories and keys:
- display: theme, defaultShiftsView, currency (e.g., "kr", "$", "€", "£"), showDashboardClockButtons (boolean)
- tax: halfTaxMonth (1-12, global half-tax month override)
- goals: monthlyGoal (baseline for all months), payrollDay (1-31), monthlyGoalsByMonth (per-month overrides, see below)
- preferences: defaultStartupTab ("home"|"shifts"|"add"|"stats"|"sharing")

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
    description:
      `Read a job's wage setup; omitted jobId uses the default job. Returns workplace, baseline/setup status, globalPaySettings, referenced tariffs, current wage (rate, tariff, supplements, overtime, tax), and upcoming/history entries with IDs and changed fields.
Use for wage, tax, payroll-day, or wage-history questions, and before manage_wage_snapshots to resolve IDs/current configuration. Use manage_account for display/preferences and global halfTaxMonth (tax) or payrollDay (goals); manage_workplace for job settings.`,
    input_schema: {
      type: "object",
      properties: {
        jobId: {
          type: "string",
          description:
            "Optional job UUID from list_workplaces. Defaults to the default job.",
        },
      },
    },
  },

  {
    name: "manage_wage_snapshots",
    description:
      `Create, update, or delete wage snapshots (wage history entries).

Wage snapshots define the user's hourly wage, tax settings, break deduction, supplements, and overtime rules for a specific time period.
Each snapshot has a from_date (when it takes effect) - the baseline snapshot has from_date=null.

Actions:
- CREATE: Creates a new wage entry. Requires from_date and tax_enabled. If tax_enabled=true, tax_percentage is required. Other fields are COPIED from current snapshot by default - only include fields you want to CHANGE.
- UPDATE: Updates an existing wage entry. Requires snapshot_id (use short ID from get_wage_info). Only include fields to change.
- DELETE: Deletes a wage entry. Requires snapshot_id.

IMPORTANT - Dichotomy between tariff and custom rates:
- Snapshots are EITHER tariff-based OR custom hourly rate, never both
- If you provide hourly_wage → automatically switches to CUSTOM mode (wage_level becomes null)
- If you provide wage_level → automatically switches to TARIFF mode (hourly_wage is looked up from preset rates)
- In tariff mode, omitted supplements and overtime default to the selected tariff version when a tariff level/date change is applied
- You do NOT need to explicitly set wage_level to null when setting a custom hourly_wage

Other notes:
- Optional jobId for CREATE targets a specific job (UUID from list_workplaces). If omitted, default job is used.
- Creating a baseline snapshot uses from_date=null and makes the job eligible for shift creation when the job is active.
- Always call get_wage_info first to see current configuration and get snapshot IDs
- For CREATE: ask for tax handling explicitly (tax_enabled and optionally tax_percentage) before calling
- For UPDATE: only specify fields to change
- Use supplements: "copy_current" to explicitly copy current supplements, or provide a new array of rules
- Omitted overtime copies/preserves the current snapshot unless Wagey is creating or recalculating a tariff snapshot, where it uses the tariff version default. Enabled overtime requires a positive weeklyThresholdHours value and rules that cover 00:00-24:00 for all days and Norwegian public holidays.
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
          description:
            "Optional job UUID from list_workplaces (CREATE only). Defaults to the default job.",
        },
        snapshot_id: {
          type: "string",
          description:
            "Snapshot ID (required for update/delete). Use short ID from get_wage_info.",
        },
        from_date: {
          type: ["string", "null"],
          description:
            "Date when new rates take effect (YYYY-MM-DD). Required for create. Null = baseline.",
        },
        hourly_wage: {
          type: "number",
          description:
            "Hourly wage in NOK (e.g., 220.5). Only include to change.",
        },
        wage_level: {
          type: ["integer", "null"],
          description:
            "Wage level 1-9 (tariff-based). Set to null to use custom hourly_wage instead.",
        },
        tax_enabled: {
          type: "boolean",
          description:
            "Whether tax deduction is enabled for this period. Required for create.",
        },
        tax_percentage: {
          type: "number",
          description:
            "Tax percentage (0-100) for this period. Required for create when tax_enabled=true.",
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
                description:
                  "Canonical end time (HH:mm, use 24:00 for end of day)",
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
                description:
                  "Optional legacy metadata field; ignored by the executor",
              },
            },
            required: ["days"],
            description:
              "Supplement rule. Use canonical fields (days/from/to/rate or percent) or alias fields (days/startTime/endTime/amount or percent).",
          },
          description:
            '"copy_current" to copy from current snapshot, or array of supplement rules. Rule keys can be canonical (from/to/rate) or alias (startTime/endTime/amount).',
        },
        overtime: {
          type: "object",
          properties: {
            enabled: {
              type: "boolean",
              description: "Whether weekly overtime supplements are enabled.",
            },
            weeklyThresholdHours: {
              type: "number",
              description:
                "Paid hours per ISO week before overtime starts, usually 40.",
            },
            rules: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  days: {
                    type: "array",
                    items: { type: "integer" },
                    description: "Weekday numbers 1-7 (Monday-Sunday)",
                  },
                  appliesOnHolidays: {
                    type: "boolean",
                    description:
                      "Whether this rule can apply on Norwegian public holidays.",
                  },
                  from: {
                    type: "string",
                    description: "Start time (HH:mm)",
                  },
                  to: {
                    type: "string",
                    description: "End time (HH:mm, use 24:00 for end of day)",
                  },
                  percent: {
                    type: "number",
                    description:
                      "Overtime supplement as percent of base hourly wage.",
                  },
                },
                required: [
                  "days",
                  "appliesOnHolidays",
                  "from",
                  "to",
                  "percent",
                ],
              },
              description:
                "Percentage-only overtime rules. Matching overtime rules use the highest percent.",
            },
          },
          required: ["enabled", "weeklyThresholdHours", "rules"],
          description:
            "Per-snapshot weekly overtime config. Set enabled=false with empty rules to disable.",
        },
      },
      required: ["action"],
    },
    input_examples: [
      {
        "action": "create",
        "from_date": "2025-02-01",
        "tax_enabled": true,
        "tax_percentage": 5,
      },
      {
        "action": "create",
        "from_date": "2025-03-01",
        "wage_level": 6,
        "tax_enabled": true,
        "tax_percentage": 10,
      },
    ],
  },

  {
    name: "manage_payroll_adjustment",
    description:
      `Inspect manual payroll adjustments only when requested; create/update/delete only on a clear mutation request. list filters by payoutStart/payoutEnd. Resolve adjustmentId with list before update/delete and clarify ambiguous targets.
Create requires amount, description, and payoutDate or payoutMonth. taxTreatment is required when tax is enabled for that payout; otherwise the backend defaults to net_manual. Update requires adjustmentId and changed fields; clearFields explicitly clears nullable fields.
Infer category from the user's reason (retro_pay/bonus when applicable, otherwise correction). Description must explain the adjustment, not repeat its category; ask for the reason if missing. Earning-period dates do not change payout timing.`,
    strict: true,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["list", "create", "update", "delete"],
          description:
            "The payroll adjustment operation to perform: list, create, update, or delete.",
        },
        adjustmentId: {
          type: ["string", "null"],
          description:
            "Short 4-8 hex prefix or full UUID of an existing payroll adjustment. Required for update/delete.",
        },
        payoutStart: {
          type: ["string", "null"],
          description:
            "Optional inclusive payout date range start as YYYY-MM-DD for list filtering.",
        },
        payoutEnd: {
          type: ["string", "null"],
          description:
            "Optional inclusive payout date range end as YYYY-MM-DD for list filtering.",
        },
        payoutDate: {
          type: ["string", "null"],
          description:
            "Payout date as YYYY-MM-DD. Required for create unless payoutMonth is provided.",
        },
        payoutMonth: {
          type: ["string", "null"],
          description:
            "Payout month as YYYY-MM. The backend derives the actual payout date using payroll day. Used only when payoutDate is null.",
        },
        jobId: {
          type: ["string", "null"],
          description:
            "Full workplace UUID from list_workplaces. Use null for no specific workplace.",
        },
        amount: {
          type: ["number", "null"],
          description:
            "Adjustment amount. Positive increases payout; negative reduces payout. Required and must be non-zero for create.",
        },
        currency: {
          type: ["string", "null"],
          description:
            "Currency or symbol to display for the adjustment, such as NOK or kr. Null uses user settings.",
        },
        category: {
          type: ["string", "null"],
          enum: ["retro_pay", "bonus", "correction", "other", null],
          description:
            "Adjustment category: retro_pay, bonus, correction, or other. Null defaults to correction for create.",
        },
        taxTreatment: {
          type: ["string", "null"],
          enum: [
            "gross_taxable",
            "net_manual",
            "excluded_from_tax_estimate",
            null,
          ],
          description:
            "Tax handling. gross_taxable estimates tax from gross; net_manual is a direct net amount; excluded_from_tax_estimate shows the amount without estimated tax. Required for create only when tax is enabled for the payout date/month.",
        },
        description: {
          type: ["string", "null"],
          description:
            "Short user-visible summary of what the adjustment is and why it exists, 1-240 characters. The category is displayed as the card title, so this must be specific context/reason, not just a category label. Required for create.",
        },
        note: {
          type: ["string", "null"],
          description: "Optional note with extra context, max 1000 characters.",
        },
        earnedFromDate: {
          type: ["string", "null"],
          description:
            "Optional earning period start date as YYYY-MM-DD. Does not affect payout date.",
        },
        earnedToDate: {
          type: ["string", "null"],
          description:
            "Optional earning period end date as YYYY-MM-DD. Must be on or after earnedFromDate when both are set.",
        },
        clearFields: {
          type: ["array", "null"],
          items: {
            type: "string",
            enum: ["jobId", "note", "earnedFromDate", "earnedToDate"],
          },
          description:
            "For update only. Nullable fields to clear explicitly. Use null when not clearing anything.",
        },
        limit: {
          type: ["number", "null"],
          description:
            "Optional maximum number of adjustments to return for list, 1-100.",
        },
      },
      required: [
        "action",
        "adjustmentId",
        "payoutStart",
        "payoutEnd",
        "payoutDate",
        "payoutMonth",
        "jobId",
        "amount",
        "currency",
        "category",
        "taxTreatment",
        "description",
        "note",
        "earnedFromDate",
        "earnedToDate",
        "clearFields",
        "limit",
      ],
      additionalProperties: false,
    },
    input_examples: [
      {
        "action": "create",
        "payoutDate": "2026-05-15",
        "amount": 1200,
        "category": "retro_pay",
        "taxTreatment": "gross_taxable",
        "description":
          "Retro pay for April that was missing from the original payout.",
        "earnedFromDate": "2026-04-01",
        "earnedToDate": "2026-04-30",
      },
    ],
  },

  // ---------------------------------------------------------------------------
  // HYPOTHETICAL EARNINGS CALCULATOR
  // ---------------------------------------------------------------------------
  {
    name: "calculate_earnings",
    description:
      `Calculate hypothetical shift earnings without writing. Use exactly one mode: hypothetical for one shift; compare for 2–5 scenarios; hypothetical_change for an existing shift plus changed times/date (query its ID first). Virtual IDs use virtual-<5-char recurring ID>-YYYY-MM-DD.
Returns gross, net if tax configured, paid_hours, and breakdown (base/supplement pay, break deduction/source, pause windows/notes); comparisons include differences and the best scenario. Resolve relative dates to YYYY-MM-DD using today's date: supplements depend on the day.`,
    input_schema: {
      type: "object",
      properties: {
        hypothetical: {
          type: "object",
          properties: {
            date: { type: "string", description: "Date (YYYY-MM-DD)" },
            start_time: { type: "string", description: "Start time (HH:mm)" },
            end_time: { type: "string", description: "End time (HH:mm)" },
            label: {
              type: "string",
              description: "Optional label for this scenario",
            },
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
              label: {
                type: "string",
                description: "Optional label for this scenario",
              },
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
            shift_id: {
              type: "string",
              description:
                "Shift ID from query_shifts (e.g. 'a1b2c' or 'virtual-a1b2c-2025-12-03')",
            },
            changes: {
              type: "object",
              properties: {
                start_time: {
                  type: "string",
                  description: "New start time (HH:mm)",
                },
                end_time: {
                  type: "string",
                  description: "New end time (HH:mm)",
                },
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
      {
        "compare": [
          {
            "date": "2025-01-24",
            "start_time": "12:00",
            "end_time": "18:00",
            "label": "Day shift",
          },
          {
            "date": "2025-01-24",
            "start_time": "16:00",
            "end_time": "22:00",
            "label": "Evening shift",
          },
        ],
      },
      {
        "hypothetical_change": {
          "shift_id": "virtual-b3c4d-2025-01-20",
          "changes": {
            "end_time": "22:00",
          },
        },
      },
    ],
  },

  // ---------------------------------------------------------------------------
  // WORKPLACES
  // ---------------------------------------------------------------------------
  {
    name: "list_workplaces",
    description:
      `List jobs with id, name, color, isDefault, isArchived, archivedAt, hasBaselineSnapshot, requiresPaySetup, and paySetupStatus (configured/pay_setup_required/archived). Includes archived jobs unless includeArchived=false.
Resolve named jobs before filtering wages/shifts or mutating jobs. Pass returned UUID as jobId. Before creating shifts, ensure the job has configured pay; create its baseline wage snapshot if required.`,
    input_schema: {
      type: "object",
      properties: {
        includeArchived: {
          type: "boolean",
          description: "Include archived jobs in the result. Default: true",
        },
      },
    },
  },

  {
    name: "manage_workplace",
    description:
      `Create a job with name and optional color/payrollDay/monthlyGoal/halfTaxMonth. Other actions require jobId from list_workplaces; update includes changed fields.
Default jobs and the last active job cannot be archived/deleted. Archive jobs with shifts/payroll adjustments instead of deleting. Archived jobs must be unarchived before adding shifts.
After create, explain pay setup is required; create a baseline via manage_wage_snapshots with jobId and from_date=null before shifts can be added.`,
    input_schema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: [
            "create",
            "update",
            "set_default",
            "archive",
            "unarchive",
            "delete",
          ],
          description: "The operation to perform",
        },
        jobId: {
          type: "string",
          description:
            "Job UUID. Required for update, set_default, archive, unarchive, and delete",
        },
        name: {
          type: "string",
          description: "Job name (1-100 chars). Required for create",
        },
        color: {
          type: ["string", "null"],
          description: "Hex color like #22C55E, or null to clear",
        },
        payrollDay: {
          type: "integer",
          description: "Payroll day of month (1-31). Optional for create.",
        },
        halfTaxMonth: {
          type: ["integer", "null"],
          description: "Half-tax month (11 or 12), or null to disable",
        },
        monthlyGoal: {
          type: ["integer", "null"],
          description:
            "Monthly goal amount (integer) or null. Optional for create.",
        },
      },
      required: ["action"],
    },
  },

  // ---------------------------------------------------------------------------
  // FRIENDS & SHARING
  // ---------------------------------------------------------------------------
  {
    name: "list_friends",
    description:
      `List friends and sharing relationship status in both directions.

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
          description:
            "Include blocked/hidden sharers in results. Default: true",
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
  },

  {
    name: "query_friend_shifts",
    description:
      `Read a friend's shared shifts; resolve friendId with list_friends and require sharesWithMe=true. Honor explicit no-access results.
mode="featured" returns active > upcoming > past preview; mode="shifts" (default) returns filtered shifts. Filters/sorting match query_shifts; jobId refers to the friend's job. Default range is current week; use 2000-01-01 through today for all-time questions. Sort by the relevant column and explicit direction before limit for extrema. Use null for unused filters, never empty strings.`,
    input_schema: {
      type: "object",
      properties: {
        mode: {
          type: "string",
          enum: ["shifts", "featured"],
          description:
            "Use featured for now/next/last/recent friend shift preview; use shifts for full viewing/filtering.",
        },
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
          description:
            "Only shifts starting at or after this time (HH:mm). Use null if no lower time filter is needed; never send an empty string.",
        },
        maxTime: {
          type: "string",
          description:
            "Only shifts starting at or before this time (HH:mm). Use null if no upper time filter is needed; never send an empty string.",
        },
        weekdays: {
          type: "array",
          items: { type: "integer" },
          description: "Filter by weekday (0=Sun..6=Sat)",
        },
        sortBy: {
          type: "string",
          enum: [
            "date_latest",
            "date_earliest",
            "date",
            "day",
            "start",
            "end",
            "hours",
            "earnings",
            "gross",
            "net",
            "workplace",
            "id",
          ],
          description:
            "Column to sort by (default: date_latest; date is a legacy alias for date_latest; earnings is an alias for gross)",
        },
        sortDirection: {
          type: "string",
          enum: ["asc", "desc"],
          description:
            "Optional sort direction. Use asc for shortest/lowest/earliest and desc for longest/highest/latest. Legacy defaults: date_latest/date desc, date_earliest asc, hours/earnings desc.",
        },
        jobId: {
          type: "string",
          description: "Filter to a specific workplace/job of the friend",
        },
      },
      required: ["friendId"],
    },
  },

  // ---------------------------------------------------------------------------
  // ADVANCED SHIFT OPERATIONS
  // ---------------------------------------------------------------------------
  {
    name: "query_friend_featured_shift",
    strict: true,
    description:
      `Get the featured shift preview for a friend (active > upcoming > past), using the same logic as the friends page.

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
- update_custom_pause_windows: shiftId, customPauseWindows, optional recurringId+shiftDate
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
            "update_custom_pause_windows",
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
          description:
            "Shift ID for update_custom_pause_windows, update_custom_supplements, or clear_shift_snapshots",
        },
        customPauseWindows: {
          type: ["object", "null"],
          description: "Custom pause windows payload or null to clear",
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
    input_examples: [{
      action: "submit",
      message: "Would love better weekend filters in stats.",
    }, { action: "list" }],
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
    input_examples: [{ action: "view" }, {
      action: "update_name",
      firstName: "Hjalmar",
    }],
  },
];

const hiddenToolNames = new Set([
  "draft_recurring_shift",
  "confirm_recurring_shift",
  "manage_recurring_exclusion",
  "manage_settings",
  "query_friend_featured_shift",
  "manage_feedback",
  "manage_profile",
]);

export const tools: FunctionTool[] = allTools.filter((tool) =>
  !hiddenToolNames.has(tool.name)
);

/**
 * Tool name type
 */
export type ToolName =
  | "manage_shift"
  | "query_shifts"
  | "query_events"
  | "manage_event"
  | "plan_schedule"
  | "calculate_wages"
  | "draft_recurring_shift"
  | "confirm_recurring_shift"
  | "manage_recurring_shift"
  | "manage_recurring_exclusion"
  | "get_statistics"
  | "manage_account"
  | "manage_settings"
  | "manage_workplace"
  | "get_wage_info"
  | "manage_wage_snapshots"
  | "manage_payroll_adjustment"
  | "calculate_earnings"
  | "list_workplaces"
  | "list_friends"
  | "manage_friend_sharing"
  | "query_friend_shifts"
  | "query_friend_featured_shift"
  | "manage_shift_advanced"
  | "manage_feedback"
  | "manage_profile"
  | "web_fetch";

/**
 * Tool result type
 */
export type ToolResult = {
  success: boolean;
  code?: string;
  message: string;
  action?: string;
  validationErrors?: Array<{ field: string; message: string }>;
  missingRequiredFields?: string[];
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
