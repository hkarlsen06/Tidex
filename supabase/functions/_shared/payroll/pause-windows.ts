import type { CustomPauseWindows, HHMM, PauseWindow, WagePeriod } from "./types.ts";

type PauseInterval = {
  start: number;
  end: number;
};

const DATE_RE = /^\d{2}:\d{2}$/;

function normalizeTime(value: string): HHMM | null {
  if (!DATE_RE.test(value)) return null;
  const [hours, minutes] = value.split(":").map(Number);
  if (!Number.isInteger(hours) || !Number.isInteger(minutes)) return null;
  if (hours < 0 || hours > 24 || minutes < 0 || minutes > 59) return null;
  if (hours === 24 && minutes !== 0) return null;
  return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}` as HHMM;
}

function toMinutes(value: string): number {
  const [hours, minutes] = value.split(":").map(Number);
  return (hours * 60) + minutes;
}

function toHHMM(value: number): HHMM {
  const rounded = Math.round(value);
  const normalized = ((rounded % (24 * 60)) + (24 * 60)) % (24 * 60);
  if (rounded > 0 && normalized === 0) {
    return "24:00" as HHMM;
  }
  const hours = Math.floor(normalized / 60);
  const minutes = normalized % 60;
  return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}` as HHMM;
}

export function normalizeCustomPauseWindows(
  value: CustomPauseWindows | null | undefined,
): CustomPauseWindows | null {
  if (!value) return null;

  const normalized = value.windows
    .map((window) => {
      const start = normalizeTime(window.start);
      const end = normalizeTime(window.end);
      if (!start || !end || start === end) {
        return null;
      }
      return { start, end } satisfies PauseWindow;
    })
    .filter((window): window is PauseWindow => window !== null);

  if (normalized.length === 0) return null;

  const unique = Array.from(
    new Map(normalized.map((window) => [`${window.start}-${window.end}`, window])).values(),
  ).sort((a, b) => {
    if (a.start === b.start) return a.end.localeCompare(b.end);
    return a.start.localeCompare(b.start);
  });

  return unique.length > 0 ? { windows: unique } : null;
}

export function normalizeDateSpecificPauseWindows(
  value: Record<string, CustomPauseWindows> | null | undefined,
): Record<string, CustomPauseWindows> | null {
  if (!value) return null;

  const normalizedEntries = Object.entries(value)
    .map(([isoDate, pauseWindows]) => {
      const normalized = normalizeCustomPauseWindows(pauseWindows);
      if (!normalized || !/^\d{4}-\d{2}-\d{2}$/.test(isoDate)) {
        return null;
      }
      return [isoDate, normalized] as const;
    })
    .filter((entry): entry is readonly [string, CustomPauseWindows] => entry !== null);

  return normalizedEntries.length > 0 ? Object.fromEntries(normalizedEntries) : null;
}

function clippedIntervals(
  pauseWindows: CustomPauseWindows,
  shiftStartTime: string,
  shiftEndTime: string,
): PauseInterval[] {
  const shiftStart = toMinutes(shiftStartTime);
  let shiftEnd = toMinutes(shiftEndTime);
  if (shiftEnd <= shiftStart) {
    shiftEnd += 24 * 60;
  }

  const intervals: PauseInterval[] = [];

  for (const window of pauseWindows.windows) {
    const windowStart = toMinutes(window.start);
    let windowEnd = toMinutes(window.end);
    if (windowEnd <= windowStart) {
      windowEnd += 24 * 60;
    }

    for (const base of [0, 24 * 60]) {
      const start = windowStart + base;
      const end = windowEnd + base;
      const clippedStart = Math.max(start, shiftStart);
      const clippedEnd = Math.min(end, shiftEnd);
      if (clippedEnd > clippedStart) {
        intervals.push({ start: clippedStart, end: clippedEnd });
      }
    }
  }

  intervals.sort((a, b) => (a.start === b.start ? a.end - b.end : a.start - b.start));

  const merged: PauseInterval[] = [];
  for (const interval of intervals) {
    const current = merged[merged.length - 1];
    if (!current || interval.start > current.end) {
      merged.push({ ...interval });
    } else {
      current.end = Math.max(current.end, interval.end);
    }
  }

  return merged;
}

export function applyCustomPauseWindowClipping(
  periods: WagePeriod[],
  pauseWindows: CustomPauseWindows,
  shiftStartTime: string,
  shiftEndTime: string,
): { periods: WagePeriod[]; deductedHours: number; appliedPauseWindows?: PauseWindow[] } {
  const normalized = normalizeCustomPauseWindows(pauseWindows);
  if (!normalized || periods.length === 0) {
    return { periods, deductedHours: 0 };
  }

  const intervals = clippedIntervals(normalized, shiftStartTime, shiftEndTime);
  if (intervals.length === 0) {
    return { periods, deductedHours: 0 };
  }

  const clipped: WagePeriod[] = [];

  for (const period of periods) {
    let cursor = period.fromMin;

    for (const interval of intervals) {
      if (interval.end <= cursor || interval.start >= period.toMin) {
        continue;
      }

      const overlapStart = Math.max(cursor, interval.start);
      const overlapEnd = Math.min(period.toMin, interval.end);

      if (overlapStart > cursor) {
        clipped.push({
          ...period,
          fromMin: cursor,
          toMin: overlapStart,
        });
      }

      cursor = Math.max(cursor, overlapEnd);
      if (cursor >= period.toMin) break;
    }

    if (cursor < period.toMin) {
      clipped.push({
        ...period,
        fromMin: cursor,
        toMin: period.toMin,
      });
    }
  }

  const deductedMinutes = intervals.reduce((sum, interval) => sum + (interval.end - interval.start), 0);

  return {
    periods: clipped.filter((period) => period.toMin > period.fromMin),
    deductedHours: deductedMinutes / 60,
    appliedPauseWindows: intervals.map((interval) => ({
      start: toHHMM(interval.start),
      end: toHHMM(interval.end),
    })),
  };
}
