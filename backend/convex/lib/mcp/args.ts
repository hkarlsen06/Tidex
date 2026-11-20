import { ToolError } from "./shiftTimes";

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
