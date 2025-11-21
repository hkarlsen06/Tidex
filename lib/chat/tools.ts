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
 * Tool Definitions (OpenAI format)
 */
export const tools: Tool[] = [
  {
    type: "function",
    function: {
      name: "add_shift",
      description:
        "Create one or more new shifts. Accepts multiple dates with same start/end times for batch creation.",
      parameters: {
        type: "object",
        properties: {
          dates: {
            type: "array",
            items: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            },
            description: "ISO date strings (YYYY-MM-DD) for the shifts to create",
            minItems: 1,
          },
          start: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "Start time in HH:mm format (24-hour)",
          },
          end: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "End time in HH:mm format (24-hour)",
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
      description:
        "Modify an existing shift's date or times. Requires shift ID from query_shifts.",
      parameters: {
        type: "object",
        properties: {
          shiftId: {
            type: "string",
            format: "uuid",
            description: "ID of the shift to update",
          },
          date: {
            type: "string",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            description: "New date in ISO format (YYYY-MM-DD)",
          },
          start: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "New start time in HH:mm format",
          },
          end: {
            type: "string",
            pattern: "^\\d{2}:\\d{2}$",
            description: "New end time in HH:mm format",
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
      description:
        "Delete a single shift. Requires shift ID from query_shifts.",
      parameters: {
        type: "object",
        properties: {
          shiftId: {
            type: "string",
            format: "uuid",
            description: "ID of the shift to delete",
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
      description:
        "Delete multiple shifts at once. Requires shift IDs from query_shifts.",
      parameters: {
        type: "object",
        properties: {
          shiftIds: {
            type: "array",
            items: {
              type: "string",
              format: "uuid",
            },
            description: "Array of shift IDs to delete",
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
      description:
        "Retrieve shifts within a date range. Required before update/delete operations to get shift IDs.",
      parameters: {
        type: "object",
        properties: {
          startDate: {
            type: "string",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            description: "Start date for query range (YYYY-MM-DD)",
          },
          endDate: {
            type: "string",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            description: "End date for query range (YYYY-MM-DD)",
          },
          limit: {
            type: "integer",
            minimum: 1,
            maximum: 100,
            default: 30,
            description: "Maximum number of shifts to return",
          },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "calculate_wages",
      description:
        "Calculate total wages for shifts. Supports three methods: (1) date range via startDate+endDate, (2) ISO week via week+year, or (3) specific shifts via shiftIds. Use only ONE method per call.",
      parameters: {
        type: "object",
        properties: {
          shiftIds: {
            type: "array",
            items: {
              type: "string",
              format: "uuid",
            },
            description: "Array of shift IDs to calculate wages for",
          },
          startDate: {
            type: "string",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            description: "Start date for range calculation (YYYY-MM-DD)",
          },
          endDate: {
            type: "string",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
            description: "End date for range calculation (YYYY-MM-DD)",
          },
          week: {
            type: "integer",
            minimum: 1,
            maximum: 53,
            description: "ISO week number (1-53) for calculation",
          },
          year: {
            type: "integer",
            minimum: 2020,
            maximum: 2100,
            description: "Year for week-based calculation",
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
  | "add_shift"
  | "update_shift"
  | "delete_shift"
  | "bulk_delete_shifts"
  | "query_shifts"
  | "calculate_wages";

/**
 * Tool result type
 */
export type ToolResult = {
  success: boolean;
  message: string;
  data?: unknown;
};
