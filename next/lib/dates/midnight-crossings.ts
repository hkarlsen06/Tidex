/**
 * Count the number of midnight boundaries crossed between two dates.
 * Users perceive "1 day" as "tomorrow", not "24 hours from now".
 *
 * @example
 * // If now is Jan 15 at 11pm and target is Jan 16 at 1am (2 hours away)
 * // This returns 1 because one midnight was crossed
 * countMidnightCrossings(now, target) // => 1
 */
export function countMidnightCrossings(from: Date, to: Date): number {
  const fromMidnight = new Date(from);
  fromMidnight.setHours(0, 0, 0, 0);

  const toMidnight = new Date(to);
  toMidnight.setHours(0, 0, 0, 0);

  const diffDays = Math.round(
    (toMidnight.getTime() - fromMidnight.getTime()) / (1000 * 60 * 60 * 24)
  );
  return Math.abs(diffDays);
}
