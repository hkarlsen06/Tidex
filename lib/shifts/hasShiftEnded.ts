import { ShiftRow } from "@/lib/payroll";

type ShiftLike = Pick<ShiftRow, "shift_date" | "start_time" | "end_time">;

function parseTime(time: string): { hours: number; minutes: number } {
  const [hoursPart, minutesPart] = time.split(":");
  const hours = Number.parseInt(hoursPart ?? "0", 10);
  const minutes = Number.parseInt(minutesPart ?? "0", 10);

  return {
    hours: Number.isFinite(hours) ? hours : 0,
    minutes: Number.isFinite(minutes) ? minutes : 0,
  };
}

function buildDate(shiftDate: string, time: string): Date {
  const [yearPart, monthPart, dayPart] = shiftDate.split("-");
  const year = Number.parseInt(yearPart ?? "0", 10);
  const month = Number.parseInt(monthPart ?? "1", 10) - 1;
  const day = Number.parseInt(dayPart ?? "1", 10);

  const { hours, minutes } = parseTime(time);

  return new Date(year, month, day, hours, minutes, 0, 0);
}

export function hasShiftEnded(
  shift: ShiftLike,
  referenceDate: Date = new Date()
): boolean {
  const start = buildDate(shift.shift_date, shift.start_time);
  const end = buildDate(shift.shift_date, shift.end_time);

  if (end <= start) {
    end.setDate(end.getDate() + 1);
  }

  return end <= referenceDate;
}
