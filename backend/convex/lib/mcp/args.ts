import { parseMonth } from "./payPeriod";
import { addDays, parseDate, parseRange, ToolError } from "./shiftTimes";

// Checks for tool arguments that any area's parser can use. Each throws ToolError with a
// message for the agent.

export type Args = Record<string, unknown>;

export const MAX_RANGE_DAYS = 366;

export function allowOnly(args: Args, names: string[]) {
  const unknown = Object.keys(args).filter((key) => !names.includes(key));
  if (unknown.length > 0) throw new ToolError(`Unknown argument: ${unknown.join(", ")}.`);
}

// Strict clients send null for an optional argument they leave out.
export const omitted = (value: unknown) => value === undefined || value === null;

export const optional = <T>(value: unknown, parse: (value: unknown) => T) => (omitted(value) ? undefined : parse(value));

export function optionalString(value: unknown, field: string, max = 100): string | undefined {
  if (omitted(value)) return undefined;
  if (typeof value !== "string" || value.length > max) throw new ToolError(`${field} must be text of at most ${max} characters.`);
  return value;
}

export function requiredString(value: unknown, field: string): string {
  const parsed = optionalString(value, field);
  if (parsed === undefined || parsed === "") throw new ToolError(`${field} is required.`);
  return parsed;
}

export const today = () => new Date().toISOString().slice(0, 10);

/** A date within five years of today, which catches a mistyped year. */
export function nearDate(value: unknown, field: string): string {
  const date = parseDate(value, field);
  const now = today();
  if (date < addDays(now, -5 * 366) || date > addDays(now, 5 * 366)) throw new ToolError(`${field} must be within five years of today.`);
  return date;
}

export function integer(value: unknown, field: string, min: number, max: number): number {
  if (!Number.isInteger(value) || (value as number) < min || (value as number) > max) {
    throw new ToolError(`${field} must be a whole number from ${min} to ${max}.`);
  }
  return value as number;
}

export function numberRange(value: unknown, field: string, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max) {
    throw new ToolError(`${field} must be a number from ${min} to ${max}.`);
  }
  return value;
}

export function positive(value: unknown, field: string, max: number): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0 || value > max) {
    throw new ToolError(`${field} must be a number above 0 and at most ${max}.`);
  }
  return value;
}

export function boolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") throw new ToolError(`${field} must be true or false.`);
  return value;
}

export function oneOf<T extends string>(value: unknown, field: string, values: readonly T[]): T {
  if (!values.includes(value as T)) throw new ToolError(`${field} must be one of: ${values.join(", ")}.`);
  return value as T;
}

export function list(value: unknown, field: string, max: number): unknown[] {
  if (!Array.isArray(value)) throw new ToolError(`${field} must be a list.`);
  if (value.length > max) throw new ToolError(`${field} can have at most ${max} entries.`);
  return value;
}

/** Text that is not blank after trimming, at most `max` characters. */
export function text(value: unknown, field: string, max: number): string {
  const parsed = optionalString(value, field, max)?.trim();
  if (!parsed) throw new ToolError(`${field} is required and can't be blank.`);
  return parsed;
}

export type DateQuery = {
  month?: string;
  from?: string;
  to?: string;
};

/**
 * Parses either `month` (YYYY-MM) or `from`/`to` (YYYY-MM-DD, up to maxDays).
 * All three may be omitted so the handler can apply a time-zone-aware default.
 */
export function parseDateQuery(args: Args, maxDays = MAX_RANGE_DAYS): DateQuery {
  const month = optional(args.month, (v) => parseMonth(v, "month").monthKey);
  const from = optional(args.from, (v) => parseDate(v, "from"));
  const to = optional(args.to, (v) => parseDate(v, "to"));
  if (month !== undefined && (from !== undefined || to !== undefined)) {
    throw new ToolError("Give either month or from/to, not both.");
  }
  if (to !== undefined && from === undefined) {
    throw new ToolError("Give from together with to, or pass month instead.");
  }
  if (from !== undefined && to !== undefined) {
    parseRange(from, to, maxDays);
  }
  return {
    ...(month !== undefined ? { month } : {}),
    ...(from !== undefined ? { from } : {}),
    ...(to !== undefined ? { to } : {}),
  };
}

/** Resolves a DateQuery into concrete from/to bounds using the user's local `todayDate`. */
export function resolveDateQuery(
  query: DateQuery,
  todayDate: string,
  defaultKind: "two_weeks" | "current_month",
): { from: string; to: string; monthKey?: string } {
  if (query.month !== undefined) {
    const parsed = parseMonth(query.month);
    return { from: parsed.from, to: parsed.to, monthKey: parsed.monthKey };
  }
  if (query.from !== undefined) {
    const to = query.to ?? addDays(query.from, 13);
    parseRange(query.from, to, MAX_RANGE_DAYS);
    return { from: query.from, to };
  }
  if (defaultKind === "current_month") {
    const parsed = parseMonth(todayDate.slice(0, 7));
    return { from: parsed.from, to: parsed.to, monthKey: parsed.monthKey };
  }
  return { from: todayDate, to: addDays(todayDate, 13) };
}

// JSON Schema pieces for tool arguments, and annotation sets.

export const date = { type: "string", format: "date", description: "YYYY-MM-DD" };
export const month = { type: "string", pattern: "^\\d{4}-(0[1-9]|1[0-2])$", description: "YYYY-MM shortcut, e.g. 2026-11" };
export const time = { type: "string", pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$", description: "HH:mm, 24-hour clock" };
export const endTime = {
  type: "string",
  pattern: "^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$",
  description: "HH:mm, 24-hour clock. An end at or before start is on the next day.",
};
export const jobRef = {
  type: "string",
  description: "Job ID or job name (defaults to the default job when omitted).",
};
export const jobFilter = {
  type: "string",
  description: "Optional job ID or job name to filter results.",
};
export const friendRef = {
  type: "string",
  description: "Friend ID, username, or name from list_friends.",
};

export const readOnly = { readOnlyHint: true, openWorldHint: false };
export const adds = { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false };
export const updates = { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false };
export const destructive = { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false };
