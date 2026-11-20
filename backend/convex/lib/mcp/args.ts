import { addDays, parseDate, ToolError } from "./shiftTimes";

// Checks for tool arguments that any area's parser can use. Each throws ToolError with a
// message for the agent.

export type Args = Record<string, unknown>;

export function allowOnly(args: Args, names: string[]) {
  const unknown = Object.keys(args).filter((key) => !names.includes(key));
  if (unknown.length > 0) throw new ToolError(`Unknown argument: ${unknown.join(", ")}.`);
}

// Strict clients send null for an optional argument they leave out.
const omitted = (value: unknown) => value === undefined || value === null;

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

export function requiredRevision(value: unknown, listTool: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new ToolError(`revision is required. Get it from ${listTool}.`);
  return value;
}

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

export function boolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") throw new ToolError(`${field} must be true or false.`);
  return value;
}

export function oneOf<T extends string>(value: unknown, field: string, values: readonly T[]): T {
  if (!values.includes(value as T)) throw new ToolError(`${field} must be one of ${values.join(", ")}.`);
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

// JSON Schema pieces for tool arguments, and annotation sets.

export const date = { type: "string", format: "date", description: "YYYY-MM-DD" };
export const time = { type: "string", pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$", description: "HH:mm, 24-hour clock" };
export const endTime = {
  type: "string",
  pattern: "^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$",
  description: "HH:mm, 24-hour clock. An end at or before the start is on the next day.",
};
export const revision = (listTool: string) => ({
  type: "number",
  description: `The revision from ${listTool}. A change made since then makes the call fail; list again.`,
});
export const jobId = { type: "string", description: "A job_id from list_jobs" };

export const readOnly = { readOnlyHint: true, openWorldHint: false };
export const adds = { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false };
export const changes = { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false };
