/**
 * Calculates the relative time between now and a given shift date/time in Norwegian
 * @param shiftDate - ISO date string (YYYY-MM-DD)
 * @param shiftTime - Time string (HH:MM)
 * @returns Relative time string in Norwegian (e.g., "I morgen", "Om 4 dager", "12t & 13min siden")
 */
export function getRelativeTime(shiftDate: string, shiftTime: string): string {
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
      return isFuture ? `Om ${m}min` : `${m}min siden`;
    }

    if (m === 0) {
      return isFuture ? `Om ${h}t` : `${h}t siden`;
    }

    return isFuture ? `Om ${h}t & ${m}min` : `${h}t & ${m}min siden`;
  }

  // Check if tomorrow
  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const isTomorrow =
    shiftDateTime.getDate() === tomorrow.getDate() &&
    shiftDateTime.getMonth() === tomorrow.getMonth() &&
    shiftDateTime.getFullYear() === tomorrow.getFullYear();

  if (isFuture && isTomorrow) {
    return 'I morgen';
  }

  // Check if yesterday
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const isYesterday =
    shiftDateTime.getDate() === yesterday.getDate() &&
    shiftDateTime.getMonth() === yesterday.getMonth() &&
    shiftDateTime.getFullYear() === yesterday.getFullYear();

  if (!isFuture && isYesterday) {
    return 'I går';
  }

  // For multiple days
  if (diffDays === 1) {
    return isFuture ? 'Om 1 dag' : '1 dag siden';
  }

  return isFuture ? `Om ${diffDays} dager` : `${diffDays} dager siden`;
}
