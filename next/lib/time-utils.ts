/**
 * Clean time string to HH:mm format
 *
 * Handles various input formats:
 * - "12:30:00+01:00" -> "12:30"
 * - "12:30:00-05:00" -> "12:30"
 * - "12:30+01:00" -> "12:30"
 * - "12:30:00" -> "12:30"
 * - "12:30" -> "12:30"
 *
 * @param time - Time string in various formats
 * @returns Time string in HH:mm format
 */
export function cleanTime(time: string): string {
  if (!time) return time;

  // First, remove timezone offset (e.g., "+01:00" or "-05:00")
  // Split on + or - but keep the first part only
  let cleaned = time;
  const plusIndex = cleaned.indexOf('+');
  const minusIndex = cleaned.lastIndexOf('-'); // lastIndexOf to avoid catching negative in time

  if (plusIndex > 0) {
    cleaned = cleaned.substring(0, plusIndex);
  } else if (minusIndex > 2) { // Must be beyond position 2 to be timezone, not part of time
    cleaned = cleaned.substring(0, minusIndex);
  }

  // Now extract just HH:MM (first 5 characters)
  return cleaned.substring(0, 5);
}
