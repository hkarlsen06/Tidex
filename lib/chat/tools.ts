/**
 * Wagey Chat Tools
 *
 * Tool definitions for AI agent to manage shifts
 */

import { z } from "zod";
import type { Tool } from "@/lib/services/openrouter";

/**
 * Manage Shift Tool Schema (Consolidated CRUD)
 */
export const manageShiftSchema = z.object({
  action: z
    .enum(["create", "update", "delete"])
    .describe("Action to perform: create new shift(s), update existing shift, or delete shift(s)"),
  dates: z
    .array(z.string().regex(/^\d{4}-\d{2}-\d{2}$/))
    .min(1)
    .optional()
    .describe("[create] ISO date strings (YYYY-MM-DD) for the shifts to create"),
  start: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .optional()
    .describe("[create/update] Start time in HH:mm format (24-hour)"),
  end: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .optional()
    .describe("[create/update] End time in HH:mm format (24-hour)"),
  shiftId: z
    .string()
    .uuid()
    .optional()
    .describe("[update/delete] ID of the shift to update or delete (for single operations)"),
  shiftIds: z
    .array(z.string().uuid())
    .min(1)
    .optional()
    .describe("[delete] Array of shift IDs to delete (for bulk delete)"),
  date: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe("[update] New date in ISO format (YYYY-MM-DD)"),
});

export type ManageShiftInput = z.infer<typeof manageShiftSchema>;

/**
 * Query Shifts Tool Schema
 */
export const queryShiftsSchema = z.object({
  startDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe("Start date for query range (YYYY-MM-DD)"),
  endDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe("End date for query range (YYYY-MM-DD)"),
  limit: z
    .number()
    .int()
    .min(1)
    .max(100)
    .optional()
    .default(30)
    .describe("Maximum number of shifts to return"),
  minTime: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .optional()
    .describe("Filter shifts starting at or after this time (HH:mm)"),
  maxTime: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .optional()
    .describe("Filter shifts starting at or before this time (HH:mm)"),
  weekdays: z
    .array(z.number().int().min(0).max(6))
    .optional()
    .describe("Filter by weekdays (0=Sunday, 1=Monday, ..., 6=Saturday)"),
  sortBy: z
    .enum(["date", "earnings", "hours"])
    .optional()
    .default("date")
    .describe("Sort results by: date (default), earnings, or hours"),
});

export type QueryShiftsInput = z.infer<typeof queryShiftsSchema>;

/**
 * Calculate Wages Tool Schema (Date range only)
 */
export const calculateWagesSchema = z.object({
  startDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .describe("Start date for calculation (YYYY-MM-DD)"),
  endDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .describe("End date for calculation (YYYY-MM-DD)"),
});

export type CalculateWagesInput = z.infer<typeof calculateWagesSchema>;

/**
 * Draft Series Shift Tool Schema (Step 1 of 2)
 */
export const draftSeriesShiftSchema = z.object({
  selectedDays: z
    .record(z.string(), z.string().regex(/^\d{4}-\d{2}-\d{2}$/))
    .describe(
      "Weekday anchors: { '0': '2025-01-19', '3': '2025-01-22' } where keys are 0=Sunday through 6=Saturday"
    ),
  start: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .describe("Start time in HH:mm format (24-hour)"),
  end: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .describe("End time in HH:mm format (24-hour)"),
  repeatIntervalWeeks: z
    .number()
    .int()
    .min(0)
    .max(8)
    .describe("Repetition interval: 0=weekly, 1=every 2 weeks, 2=every 3 weeks, etc."),
  endCondition: z
    .nullable(
      z.object({
        type: z.enum(["months", "years", "end_date"]).describe("Type of end condition"),
        value: z.union([z.number(), z.string()]).describe("Value: number for months/years, ISO date string for end_date"),
      })
    )
    .describe("When the series ends (null = infinite)"),
});

export type DraftSeriesShiftInput = z.infer<typeof draftSeriesShiftSchema>;

/**
 * Confirm Series Shift Tool Schema (Step 2 of 2)
 */
export const confirmSeriesShiftSchema = z.object({
  selectedDays: z
    .record(z.string(), z.string().regex(/^\d{4}-\d{2}-\d{2}$/))
    .describe(
      "Same weekday anchors from draft step"
    ),
  start: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .describe("Same start time from draft step"),
  end: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .describe("Same end time from draft step"),
  repeatIntervalWeeks: z
    .number()
    .int()
    .min(0)
    .max(8)
    .describe("Same repetition interval from draft step"),
  endCondition: z
    .nullable(
      z.object({
        type: z.enum(["months", "years", "end_date"]),
        value: z.union([z.number(), z.string()]),
      })
    )
    .describe("Same end condition from draft step"),
  conflictResolution: z
    .enum(["keep_existing", "exclude_conflicts"])
    .describe(
      "How to handle conflicts: 'keep_existing' = both shifts coexist, 'exclude_conflicts' = series skips conflict dates"
    ),
});

export type ConfirmSeriesShiftInput = z.infer<typeof confirmSeriesShiftSchema>;

/**
 * Manage Series Shift Tool Schema (Consolidated update/delete/query)
 */
export const manageSeriesShiftSchema = z.object({
  action: z
    .enum(["update", "delete", "query"])
    .describe("Action to perform: update series parameters, delete series, or query series details"),
  seriesId: z
    .string()
    .uuid()
    .optional()
    .describe("ID of the series shift (required for update/delete, optional for query)"),
  selectedDays: z
    .record(z.string(), z.string().regex(/^\d{4}-\d{2}-\d{2}$/))
    .optional()
    .describe("[update] New weekday anchors"),
  start: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .optional()
    .describe("[update] New start time"),
  end: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .optional()
    .describe("[update] New end time"),
  repeatIntervalWeeks: z
    .number()
    .int()
    .min(0)
    .max(8)
    .optional()
    .describe("[update] New repetition interval"),
  endCondition: z
    .nullable(
      z.object({
        type: z.enum(["months", "years", "end_date"]),
        value: z.union([z.number(), z.string()]),
      })
    )
    .optional()
    .describe("[update] New end condition"),
});

export type ManageSeriesShiftInput = z.infer<typeof manageSeriesShiftSchema>;

/**
 * Manage Series Exclusion Tool Schema (Consolidated)
 */
export const manageSeriesExclusionSchema = z.object({
  seriesId: z.string().uuid().describe("ID of the series shift"),
  date: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .describe("ISO date to add/remove from exclusions (YYYY-MM-DD)"),
  action: z.enum(["add", "remove"]).describe("Whether to add or remove the exclusion"),
});

export type ManageSeriesExclusionInput = z.infer<typeof manageSeriesExclusionSchema>;

/**
 * Get Statistics Tool Schema
 */
export const getStatisticsSchema = z.object({
  metric: z
    .enum([
      "current_month",
      "last_month",
      "year_to_date",
      "last_6_months",
      "this_week",
      "by_day_of_week",
      "monthly_goal",
      "supplement_breakdown",
    ])
    .describe(
      "Statistics metric to retrieve: current_month=current month totals, last_month=last month totals, year_to_date=YTD totals, last_6_months=6 month trend, this_week=daily breakdown Mon-Sun, by_day_of_week=average per weekday, monthly_goal=goal progress, supplement_breakdown=base vs supplement pay split"
    ),
  year: z
    .number()
    .int()
    .min(2020)
    .max(2100)
    .optional()
    .describe("Year for stats (defaults to current year)"),
  month: z
    .number()
    .int()
    .min(1)
    .max(12)
    .optional()
    .describe("Month for stats (1-12, defaults to current month)"),
});

export type GetStatisticsInput = z.infer<typeof getStatisticsSchema>;

/**
 * Manage Settings Tool Schema (Consolidated view/update)
 */
export const manageSettingsSchema = z.object({
  action: z
    .enum(["view", "update"])
    .optional()
    .default("view")
    .describe("Action: 'view' to read settings (default), 'update' to modify settings"),
  category: z
    .enum(["display", "payroll", "tax", "goals", "preferences"])
    .optional()
    .describe("[update] Settings category to update"),
  settings: z
    .record(z.string(), z.any())
    .optional()
    .describe("[update] Settings object with key-value pairs to update"),
});

export type ManageSettingsInput = z.infer<typeof manageSettingsSchema>;

/**
 * Tool Definitions (OpenAI format)
 */
export const tools: Tool[] = [
  {
    type: "function",
    function: {
      name: "manage_shift",
      description: "Manage shifts: create new shift(s), update existing shift, or delete shift(s). Use query_shifts to get shift IDs first for update/delete.",
      parameters: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["create", "update", "delete"],
            description: "Action: 'create' for new shifts, 'update' to modify, 'delete' to remove",
          },
          dates: {
            type: "array",
            items: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            },
            description: "[create] Date(s) as YYYY-MM-DD",
            minItems: 1,
          },
          start: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "[create/update] Start time HH:mm (24-hour)",
          },
          end: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "[create/update] End time HH:mm (24-hour)",
          },
          date: {
            type: "string",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            description: "[update] New date YYYY-MM-DD",
          },
          shiftId: {
            type: "string",
            format: "uuid",
            description: "[update/delete] Shift ID for single operation",
          },
          shiftIds: {
            type: "array",
            items: {
              type: "string",
              format: "uuid",
            },
            description: "[delete] Shift IDs for bulk delete",
            minItems: 1,
          },
        },
        required: ["action"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "query_shifts",
      description: "Get shifts with optional filters. Omit dates for current week. Returns shift IDs and details.",
      parameters: {
        type: "object",
        properties: {
          startDate: {
            type: "string",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            description: "Start date YYYY-MM-DD",
          },
          endDate: {
            type: "string",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            description: "End date YYYY-MM-DD",
          },
          limit: {
            type: "integer",
            minimum: 1,
            maximum: 100,
            default: 30,
            description: "Max shifts",
          },
          minTime: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "Filter shifts starting >= this time HH:mm",
          },
          maxTime: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "Filter shifts starting <= this time HH:mm",
          },
          weekdays: {
            type: "array",
            items: {
              type: "integer",
              minimum: 0,
              maximum: 6,
            },
            description: "Filter by weekdays: 0=Sun, 1=Mon, ..., 6=Sat",
          },
          sortBy: {
            type: "string",
            enum: ["date", "earnings", "hours"],
            default: "date",
            description: "Sort by date (default), earnings, or hours",
          },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "calculate_wages",
      description: "Calculate total wages for date range. Returns gross, net, hours, tax.",
      parameters: {
        type: "object",
        properties: {
          startDate: {
            type: "string",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            description: "Start date YYYY-MM-DD",
          },
          endDate: {
            type: "string",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            description: "End date YYYY-MM-DD",
          },
        },
        required: ["startDate", "endDate"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "draft_series_shift",
      description: "Step 1/2: Validate recurring shift pattern, detect conflicts. Does NOT create.",
      parameters: {
        type: "object",
        properties: {
          selectedDays: {
            type: "object",
            description: "Weekdays: {'0': 'YYYY-MM-DD'} where 0=Sun to 6=Sat",
            additionalProperties: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            },
          },
          start: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "Start HH:mm",
          },
          end: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "End HH:mm",
          },
          repeatIntervalWeeks: {
            type: "integer",
            minimum: 0,
            maximum: 8,
            description: "0=weekly, 1=biweekly, etc.",
          },
          endCondition: {
            type: ["object", "null"],
            properties: {
              type: {
                type: "string",
                enum: ["months", "years", "end_date"],
              },
              value: {
                description: "Number or date string",
              },
            },
            required: ["type", "value"],
            description: "null = infinite",
          },
        },
        required: ["selectedDays", "start", "end", "repeatIntervalWeeks", "endCondition"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "confirm_series_shift",
      description: "Step 2/2: Create recurring series after draft. Use same params + conflict choice.",
      parameters: {
        type: "object",
        properties: {
          selectedDays: {
            type: "object",
            description: "Same from draft",
            additionalProperties: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            },
          },
          start: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "Same from draft",
          },
          end: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "Same from draft",
          },
          repeatIntervalWeeks: {
            type: "integer",
            minimum: 0,
            maximum: 8,
            description: "Same from draft",
          },
          endCondition: {
            type: ["object", "null"],
            properties: {
              type: {
                type: "string",
                enum: ["months", "years", "end_date"],
              },
              value: {},
            },
            required: ["type", "value"],
            description: "Same from draft",
          },
          conflictResolution: {
            type: "string",
            enum: ["keep_existing", "exclude_conflicts"],
            description: "'keep_existing' or 'exclude_conflicts'",
          },
        },
        required: [
          "selectedDays",
          "start",
          "end",
          "repeatIntervalWeeks",
          "endCondition",
          "conflictResolution",
        ],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "manage_series_shift",
      description: "Manage recurring series: update parameters, delete series, or query series details. Use this for existing series only (not for creating new).",
      parameters: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["update", "delete", "query"],
            description: "Action: 'update' to modify series, 'delete' to remove, 'query' to get details",
          },
          seriesId: {
            type: "string",
            format: "uuid",
            description: "Series ID (required for update/delete, optional for query to get all series)",
          },
          selectedDays: {
            type: "object",
            description: "[update] New weekdays: {'0': 'YYYY-MM-DD'} where 0=Sun to 6=Sat",
            additionalProperties: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            },
          },
          start: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "[update] New start HH:mm",
          },
          end: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "[update] New end HH:mm",
          },
          repeatIntervalWeeks: {
            type: "integer",
            minimum: 0,
            maximum: 8,
            description: "[update] New interval: 0=weekly, 1=biweekly, etc.",
          },
          endCondition: {
            type: ["object", "null"],
            properties: {
              type: {
                type: "string",
                enum: ["months", "years", "end_date"],
              },
              value: {},
            },
            required: ["type", "value"],
            description: "[update] New end condition (null = infinite)",
          },
        },
        required: ["action"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "manage_series_exclusion",
      description: "Add or remove date exclusion from recurring series. Useful for holidays/exceptions.",
      parameters: {
        type: "object",
        properties: {
          seriesId: {
            type: "string",
            format: "uuid",
            description: "Series ID",
          },
          date: {
            type: "string",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            description: "Date to exclude/restore YYYY-MM-DD",
          },
          action: {
            type: "string",
            enum: ["add", "remove"],
            description: "'add' to exclude date, 'remove' to restore",
          },
        },
        required: ["seriesId", "date", "action"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_statistics",
      description: "Get statistics and analytics. Choose metric: current_month, last_month, year_to_date, last_6_months, this_week, by_day_of_week, monthly_goal, supplement_breakdown.",
      parameters: {
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
            description: "Statistic to retrieve",
          },
          year: {
            type: "integer",
            minimum: 2020,
            maximum: 2100,
            description: "Year (optional)",
          },
          month: {
            type: "integer",
            minimum: 1,
            maximum: 12,
            description: "Month 1-12 (optional)",
          },
        },
        required: ["metric"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "manage_settings",
      description: "View or update user settings. Without args, returns all settings (display, payroll, tax, goals, preferences). With args, updates specific category settings.",
      parameters: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["view", "update"],
            default: "view",
            description: "Action: 'view' to read settings (default), 'update' to modify",
          },
          category: {
            type: "string",
            enum: ["display", "payroll", "tax", "goals", "preferences"],
            description: "[update] Category: display (theme, view), payroll (wage, breaks), tax (rate, half-tax month), goals (monthly target, payroll day), preferences (time input, minute range)",
          },
          settings: {
            type: "object",
            description: "[update] Settings object with key-value pairs. Examples: {theme: 'dark'}, {monthlyGoal: 50000}, {taxPercentage: 35}",
            additionalProperties: true,
          },
        },
      },
    },
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
