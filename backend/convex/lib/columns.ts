import { reject } from "./syncWrite";

// The Postgres types of the columns the app writes, where v.string() and v.number() are
// looser than Postgres. The app decodes these as Int, Date and so on, so a value
// Postgres would have rejected must not reach other devices through a pull.
type Kind = "int2" | "int4" | "int4[]" | "numeric" | "date" | "timestamptz" | "timetz";

const columnKinds: Record<string, Record<string, Kind>> = {
  jobs: { sort_order: "int2", payroll_day: "int4", monthly_goal: "int4", archived_at: "timestamptz" },
  user_shifts: { shift_date: "date" },
  events: { start_date: "date", end_date: "date", notification_minutes_array: "int4[]" },
  recurring_shifts: { start_time: "timetz", end_time: "timetz", repeat_interval_weeks: "int2" },
  wage_snapshots: {
    from_date: "date",
    hourly_wage: "numeric",
    wage_level: "int4",
    tax_percentage: "numeric",
    break_threshold_hours: "numeric",
    break_deduction_minutes: "int4",
  },
  payroll_adjustments: {
    amount: "numeric",
    earned_from_date: "date",
    earned_to_date: "date",
    payout_date: "date",
  },
  user_settings: { monthly_goal: "int4", payroll_day: "int4", last_active: "timestamptz" },
  notification_preferences: { shift_reminder_minutes_array: "int4[]" },
};

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const TIMETZ = /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d(\.\d{1,6})?)?(Z|[+-]\d{2}(:?\d{2})?)?$/;

const isInt = (value: unknown, min: number, max: number) =>
  Number.isInteger(value) && (value as number) >= min && (value as number) <= max;

const isDate = (value: unknown) =>
  typeof value === "string" &&
  DATE.test(value) &&
  !Number.isNaN(Date.parse(`${value}T00:00:00Z`)) &&
  new Date(`${value}T00:00:00Z`).toISOString().startsWith(value);

/**
 * Rejects values the Postgres column type would have rejected, and rewrites timestamps
 * to Date.toISOString() form so they sort as strings. Changes `row` in place.
 */
export function checkColumns(table: string, row: Record<string, unknown>): void {
  for (const [column, kind] of Object.entries(columnKinds[table] ?? {})) {
    const value = row[column];
    if (value === undefined) continue;
    let ok: boolean;
    switch (kind) {
      case "int2":
        ok = isInt(value, -32768, 32767);
        break;
      case "int4":
        ok = isInt(value, -2147483648, 2147483647);
        break;
      case "int4[]":
        ok = Array.isArray(value) && value.every((n) => isInt(n, -2147483648, 2147483647));
        break;
      case "numeric":
        ok = Number.isFinite(value);
        break;
      case "date":
        ok = isDate(value);
        break;
      case "timetz":
        ok = typeof value === "string" && TIMETZ.test(value);
        break;
      case "timestamptz": {
        const ms = typeof value === "string" ? Date.parse(value) : Number.NaN;
        ok = !Number.isNaN(ms);
        if (ok) row[column] = new Date(ms).toISOString();
        break;
      }
    }
    if (!ok) reject("invalid_row", `${column} is not a valid ${kind}`);
  }
}
