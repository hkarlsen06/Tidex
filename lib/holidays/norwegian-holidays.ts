/**
 * Norwegian Public Holidays (Static)
 *
 * This module provides a lightweight implementation of Norwegian public holidays
 * without external dependencies. Norwegian holidays are stable and predictable,
 * making a static list more efficient than a 262KB worldwide holidays library.
 *
 * UPDATE ANNUALLY: Add new year's holidays in December for the upcoming year.
 *
 * Holiday Types:
 * - Fixed: Same date every year (New Year, Labor Day, Constitution Day, Christmas)
 * - Moveable: Based on Easter (calculated via Computus algorithm)
 */

// Easter dates for 2025-2030 (calculated via Computus algorithm)
// Easter Sunday falls on these dates:
const EASTER_DATES: Record<number, { month: number; day: number }> = {
  2025: { month: 4, day: 20 },  // April 20, 2025
  2026: { month: 4, day: 5 },   // April 5, 2026
  2027: { month: 3, day: 28 },  // March 28, 2027
  2028: { month: 4, day: 16 },  // April 16, 2028
  2029: { month: 4, day: 1 },   // April 1, 2029
  2030: { month: 4, day: 21 },  // April 21, 2030
};

export interface NorwegianHoliday {
  date: string; // ISO date string (YYYY-MM-DD)
  name: {
    no: string;
    en: string;
  };
}

/**
 * Calculate Easter Sunday for a given year using the Computus algorithm
 * (Anonymous Gregorian algorithm)
 */
function calculateEaster(year: number): Date {
  // Use precomputed dates if available
  if (year in EASTER_DATES) {
    const { month, day } = EASTER_DATES[year];
    return new Date(year, month - 1, day);
  }

  // Computus algorithm for years beyond our precomputed range
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;

  return new Date(year, month - 1, day);
}

/**
 * Add days to a date
 */
function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

/**
 * Format date as YYYY-MM-DD
 */
function formatDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * Generate all Norwegian public holidays for a given year
 */
export function generateNorwegianHolidays(year: number): NorwegianHoliday[] {
  const easter = calculateEaster(year);
  const holidays: NorwegianHoliday[] = [];

  // Fixed holidays
  holidays.push({
    date: `${year}-01-01`,
    name: { no: 'Første nyttårsdag', en: "New Year's Day" },
  });

  holidays.push({
    date: `${year}-05-01`,
    name: { no: 'Første mai', en: 'Labour Day' },
  });

  holidays.push({
    date: `${year}-05-17`,
    name: { no: 'Grunnlovsdag', en: 'Constitution Day' },
  });

  holidays.push({
    date: `${year}-12-25`,
    name: { no: 'Første juledag', en: 'Christmas Day' },
  });

  holidays.push({
    date: `${year}-12-26`,
    name: { no: 'Andre juledag', en: 'Boxing Day' },
  });

  // Moveable holidays (Easter-based)
  // Maundy Thursday (Skjærtorsdag) - 3 days before Easter
  holidays.push({
    date: formatDate(addDays(easter, -3)),
    name: { no: 'Skjærtorsdag', en: 'Maundy Thursday' },
  });

  // Good Friday (Langfredag) - 2 days before Easter
  holidays.push({
    date: formatDate(addDays(easter, -2)),
    name: { no: 'Langfredag', en: 'Good Friday' },
  });

  // Easter Sunday (Første påskedag)
  holidays.push({
    date: formatDate(easter),
    name: { no: 'Første påskedag', en: 'Easter Sunday' },
  });

  // Easter Monday (Andre påskedag) - 1 day after Easter
  holidays.push({
    date: formatDate(addDays(easter, 1)),
    name: { no: 'Andre påskedag', en: 'Easter Monday' },
  });

  // Ascension Day (Kristi himmelfartsdag) - 39 days after Easter
  holidays.push({
    date: formatDate(addDays(easter, 39)),
    name: { no: 'Kristi himmelfartsdag', en: 'Ascension Day' },
  });

  // Whit Sunday (Første pinsedag) - 49 days after Easter
  holidays.push({
    date: formatDate(addDays(easter, 49)),
    name: { no: 'Første pinsedag', en: 'Whit Sunday' },
  });

  // Whit Monday (Andre pinsedag) - 50 days after Easter
  holidays.push({
    date: formatDate(addDays(easter, 50)),
    name: { no: 'Andre pinsedag', en: 'Whit Monday' },
  });

  return holidays.sort((a, b) => a.date.localeCompare(b.date));
}

/**
 * Cache for generated holidays by year
 */
const holidayCache = new Map<number, NorwegianHoliday[]>();

/**
 * Get all Norwegian public holidays for a given year (cached)
 */
export function getNorwegianHolidays(year: number): NorwegianHoliday[] {
  if (!holidayCache.has(year)) {
    holidayCache.set(year, generateNorwegianHolidays(year));
  }
  return holidayCache.get(year)!;
}

/**
 * Check if a date string (YYYY-MM-DD) is a Norwegian public holiday
 */
export function isNorwegianPublicHoliday(dateStr: string): boolean {
  const year = parseInt(dateStr.substring(0, 4), 10);
  const holidays = getNorwegianHolidays(year);
  return holidays.some((h) => h.date === dateStr);
}

/**
 * Get the holiday name for a date (if it's a holiday)
 */
export function getNorwegianHolidayName(
  dateStr: string,
  locale: 'no' | 'en' = 'no'
): string | null {
  const year = parseInt(dateStr.substring(0, 4), 10);
  const holidays = getNorwegianHolidays(year);
  const holiday = holidays.find((h) => h.date === dateStr);
  return holiday ? holiday.name[locale] : null;
}
