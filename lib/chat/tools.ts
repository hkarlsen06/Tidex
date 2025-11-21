/**
 * Wagey Chat Tools
 *
 * Tool definitions for AI agent to manage shifts
 */

import { z } from "zod";
import type { Tool } from "@/lib/services/openrouter";

/**
 * Add Shift Tool Schema
 */
export const addShiftSchema = z.object({
  dates: z
    .array(z.string().regex(/^\d{4}-\d{2}-\d{2}$/))
    .min(1)
    .describe("ISO date strings (YYYY-MM-DD) for the shifts to create"),
  start: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .describe("Start time in HH:mm format (24-hour)"),
  end: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .describe("End time in HH:mm format (24-hour)"),
});

export type AddShiftInput = z.infer<typeof addShiftSchema>;

/**
 * Update Shift Tool Schema
 */
export const updateShiftSchema = z.object({
  shiftId: z.string().uuid().describe("ID of the shift to update"),
  date: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe("New date in ISO format (YYYY-MM-DD)"),
  start: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .optional()
    .describe("New start time in HH:mm format"),
  end: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .optional()
    .describe("New end time in HH:mm format"),
});

export type UpdateShiftInput = z.infer<typeof updateShiftSchema>;

/**
 * Delete Shift Tool Schema
 */
export const deleteShiftSchema = z.object({
  shiftId: z.string().uuid().describe("ID of the shift to delete"),
});

export type DeleteShiftInput = z.infer<typeof deleteShiftSchema>;

/**
 * Bulk Delete Shifts Tool Schema
 */
export const bulkDeleteShiftsSchema = z.object({
  shiftIds: z
    .array(z.string().uuid())
    .min(1)
    .describe("Array of shift IDs to delete"),
});

export type BulkDeleteShiftsInput = z.infer<typeof bulkDeleteShiftsSchema>;

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
});

export type QueryShiftsInput = z.infer<typeof queryShiftsSchema>;

/**
 * Calculate Wages Tool Schema
 */
export const calculateWagesSchema = z.object({
  shiftIds: z
    .array(z.string().uuid())
    .optional()
    .describe("Array of specific shift IDs to calculate wages for"),
  startDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe("Start date for date range calculation (YYYY-MM-DD)"),
  endDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .describe("End date for date range calculation (YYYY-MM-DD)"),
  week: z
    .number()
    .int()
    .min(1)
    .max(53)
    .optional()
    .describe("ISO week number (1-53) for calculation"),
  year: z
    .number()
    .int()
    .min(2020)
    .max(2100)
    .optional()
    .describe("Year for week calculation (defaults to current year)"),
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
 * Update Series Shift Tool Schema
 */
export const updateSeriesShiftSchema = z.object({
  seriesId: z.string().uuid().describe("ID of the series shift to update"),
  selectedDays: z
    .record(z.string(), z.string().regex(/^\d{4}-\d{2}-\d{2}$/))
    .optional()
    .describe("New weekday anchors"),
  start: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .optional()
    .describe("New start time"),
  end: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .optional()
    .describe("New end time"),
  repeatIntervalWeeks: z
    .number()
    .int()
    .min(0)
    .max(8)
    .optional()
    .describe("New repetition interval"),
  endCondition: z
    .nullable(
      z.object({
        type: z.enum(["months", "years", "end_date"]),
        value: z.union([z.number(), z.string()]),
      })
    )
    .optional()
    .describe("New end condition"),
});

export type UpdateSeriesShiftInput = z.infer<typeof updateSeriesShiftSchema>;

/**
 * Delete Series Shift Tool Schema
 */
export const deleteSeriesShiftSchema = z.object({
  seriesId: z.string().uuid().describe("ID of the series shift to delete"),
});

export type DeleteSeriesShiftInput = z.infer<typeof deleteSeriesShiftSchema>;

/**
 * Query Series Shifts Tool Schema
 */
export const querySeriesShiftsSchema = z.object({
  seriesId: z
    .string()
    .uuid()
    .optional()
    .describe("Optional: specific series ID to retrieve"),
});

export type QuerySeriesShiftsInput = z.infer<typeof querySeriesShiftsSchema>;

/**
 * Add Series Exclusion Tool Schema
 */
export const addSeriesExclusionSchema = z.object({
  seriesId: z.string().uuid().describe("ID of the series shift"),
  date: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .describe("ISO date to exclude from series (YYYY-MM-DD)"),
});

export type AddSeriesExclusionInput = z.infer<typeof addSeriesExclusionSchema>;

/**
 * Remove Series Exclusion Tool Schema
 */
export const removeSeriesExclusionSchema = z.object({
  seriesId: z.string().uuid().describe("ID of the series shift"),
  date: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .describe("ISO date to remove from exclusions (YYYY-MM-DD)"),
});

export type RemoveSeriesExclusionInput = z.infer<typeof removeSeriesExclusionSchema>;

/**
 * Tool Definitions (OpenAI format)
 */
export const tools: Tool[] = [
  {
    type: "function",
    function: {
      name: "add_shift",
      description: "Create new shifts. Supports multiple dates for batch creation.",
      parameters: {
        type: "object",
        properties: {
          dates: {
            type: "array",
            items: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            },
            description: "Date(s) as YYYY-MM-DD",
            minItems: 1,
          },
          start: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "Start time HH:mm (24-hour)",
          },
          end: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "End time HH:mm (24-hour)",
          },
        },
        required: ["dates", "start", "end"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "update_shift",
      description: "Modify shift date/times. Get ID from query_shifts first.",
      parameters: {
        type: "object",
        properties: {
          shiftId: {
            type: "string",
            format: "uuid",
            description: "Shift ID",
          },
          date: {
            type: "string",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            description: "New date YYYY-MM-DD",
          },
          start: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "New start HH:mm",
          },
          end: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "New end HH:mm",
          },
        },
        required: ["shiftId"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "delete_shift",
      description: "Delete one shift. Get ID from query_shifts first.",
      parameters: {
        type: "object",
        properties: {
          shiftId: {
            type: "string",
            format: "uuid",
            description: "Shift ID",
          },
        },
        required: ["shiftId"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "bulk_delete_shifts",
      description: "Delete multiple shifts. Get IDs from query_shifts first.",
      parameters: {
        type: "object",
        properties: {
          shiftIds: {
            type: "array",
            items: {
              type: "string",
              format: "uuid",
            },
            description: "Shift IDs",
            minItems: 1,
          },
        },
        required: ["shiftIds"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "query_shifts",
      description: "Get shifts in date range. Omit dates for current week. Returns shift IDs.",
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
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "calculate_wages",
      description: "Calculate wages. Use ONE method: (1) date range, (2) week+year, or (3) shift IDs.",
      parameters: {
        type: "object",
        properties: {
          shiftIds: {
            type: "array",
            items: {
              type: "string",
              format: "uuid",
            },
            description: "Shift IDs",
          },
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
          week: {
            type: "integer",
            minimum: 1,
            maximum: 53,
            description: "ISO week (1-53)",
          },
          year: {
            type: "integer",
            minimum: 2020,
            maximum: 2100,
            description: "Year for week",
          },
        },
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
      name: "update_series_shift",
      description: "Modify recurring series. Get ID from query_series_shifts first.",
      parameters: {
        type: "object",
        properties: {
          seriesId: {
            type: "string",
            format: "uuid",
            description: "Series ID",
          },
          selectedDays: {
            type: "object",
            description: "New weekdays",
            additionalProperties: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            },
          },
          start: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "New start",
          },
          end: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "New end",
          },
          repeatIntervalWeeks: {
            type: "integer",
            minimum: 0,
            maximum: 8,
            description: "New interval",
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
            description: "New end",
          },
        },
        required: ["seriesId"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "delete_series_shift",
      description: "Delete recurring series pattern. Does NOT delete standalone shifts.",
      parameters: {
        type: "object",
        properties: {
          seriesId: {
            type: "string",
            format: "uuid",
            description: "Series ID",
          },
        },
        required: ["seriesId"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "query_series_shifts",
      description: "Get recurring series patterns. Returns definitions, not individual shifts.",
      parameters: {
        type: "object",
        properties: {
          seriesId: {
            type: "string",
            format: "uuid",
            description: "Optional series ID",
          },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "add_series_exclusion",
      description: "Skip one occurrence of recurring series. Useful for holidays.",
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
            description: "Date to exclude YYYY-MM-DD",
          },
        },
        required: ["seriesId", "date"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "remove_series_exclusion",
      description: "Restore previously excluded occurrence to recurring series.",
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
            description: "Date to restore YYYY-MM-DD",
          },
        },
        required: ["seriesId", "date"],
      },
    },
  },
];

/**
 * Tool name type
 */
export type ToolName =
  | "add_shift"
  | "update_shift"
  | "delete_shift"
  | "bulk_delete_shifts"
  | "query_shifts"
  | "calculate_wages"
  | "draft_series_shift"
  | "confirm_series_shift"
  | "update_series_shift"
  | "delete_series_shift"
  | "query_series_shifts"
  | "add_series_exclusion"
  | "remove_series_exclusion";

/**
 * Tool result type
 */
export type ToolResult = {
  success: boolean;
  message: string;
  data?: unknown;
};
