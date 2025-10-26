import type { Dictionary } from '@/lib/i18n/dictionaries/no';

// Simple string interpolation helper
function interpolate(str: string, values: Record<string, number>): string {
  return str.replace(/\{(\w+)\}/g, (_, key) => String(values[key] ?? ''));
}

/**
 * Calculates the relative time between now and a given shift date/time
 * @param shiftDate - ISO date string (YYYY-MM-DD)
 * @param shiftTime - Time string (HH:MM)
 * @param t - Translations object from useTranslations() or getTranslations()
 * @returns Relative time string (e.g., "Tomorrow", "In 4 days", "12h & 13min ago")
 */
export function getRelativeTime(shiftDate: string, shiftTime: string, t: Dictionary): string {
  const now = new Date();

  // Parse shift date and time in local timezone
  const [hours, minutes] = shiftTime.split(':').map(Number);
  const shiftDateTime = new Date(shiftDate + 'T00:00:00');
  shiftDateTime.setHours(hours, minutes, 0, 0);

  const diffMs = shiftDateTime.getTime() - now.getTime();
  const isFuture = diffMs > 0;
  const absDiffMs = Math.abs(diffMs);

  const diffMinutes = Math.floor(absDiffMs / (1000 * 60));
  const diffHours = Math.floor(absDiffMs / (1000 * 60 * 60));
  const diffDays = Math.floor(absDiffMs / (1000 * 60 * 60 * 24));

  // For shifts very close in time (less than 24 hours)
  if (diffHours < 24) {
    const h = Math.floor(diffMinutes / 60);
    const m = diffMinutes % 60;

    if (h === 0) {
      return isFuture
        ? interpolate(t.common.relativeTime.inMinutes, { minutes: m })
        : interpolate(t.common.relativeTime.minutesAgo, { minutes: m });
    }

    if (m === 0) {
      return isFuture
        ? interpolate(t.common.relativeTime.inHours, { hours: h })
        : interpolate(t.common.relativeTime.hoursAgo, { hours: h });
    }

    return isFuture
      ? interpolate(t.common.relativeTime.inHoursAndMinutes, { hours: h, minutes: m })
      : interpolate(t.common.relativeTime.hoursAndMinutesAgo, { hours: h, minutes: m });
  }

  // Check if tomorrow
  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const isTomorrow =
    shiftDateTime.getDate() === tomorrow.getDate() &&
    shiftDateTime.getMonth() === tomorrow.getMonth() &&
    shiftDateTime.getFullYear() === tomorrow.getFullYear();

  if (isFuture && isTomorrow) {
    return t.common.relativeTime.tomorrow;
  }

  // Check if yesterday
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const isYesterday =
    shiftDateTime.getDate() === yesterday.getDate() &&
    shiftDateTime.getMonth() === yesterday.getMonth() &&
    shiftDateTime.getFullYear() === yesterday.getFullYear();

  if (!isFuture && isYesterday) {
    return t.common.relativeTime.yesterday;
  }

  // For multiple days
  if (diffDays === 1) {
    return isFuture ? t.common.relativeTime.inOneDay : t.common.relativeTime.oneDayAgo;
  }

  return isFuture
    ? interpolate(t.common.relativeTime.inDays, { days: diffDays })
    : interpolate(t.common.relativeTime.daysAgo, { days: diffDays });
}
