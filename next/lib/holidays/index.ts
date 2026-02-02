import type { Locale } from '@/lib/i18n';
import {
  isNorwegianPublicHoliday,
  getNorwegianHolidayName,
  getNorwegianHolidays,
} from './norwegian-holidays';

/**
 * Format a Date object as YYYY-MM-DD
 */
function formatDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * Check if a given date is a public holiday in Norway
 */
export function isPublicHoliday(date: Date, _locale: Locale = 'no'): boolean {
  const dateStr = formatDate(date);
  return isNorwegianPublicHoliday(dateStr);
}

/**
 * Check if a given date falls on a weekend (Saturday or Sunday)
 */
export function isWeekend(date: Date): boolean {
  const day = date.getDay();
  return day === 0 || day === 6; // 0 = Sunday, 6 = Saturday
}

/**
 * Check if a given date is a Monday
 */
export function isMonday(date: Date): boolean {
  return date.getDay() === 1;
}

/**
 * Check if a date is invalid for payroll purposes
 * Invalid = weekend, Monday, or public holiday
 */
export function isInvalidPayrollDay(date: Date, locale: Locale = 'no'): boolean {
  return isWeekend(date) || isMonday(date) || isPublicHoliday(date, locale);
}

/**
 * Get the name of a holiday (if the date is a holiday)
 */
export function getHolidayName(date: Date, locale: Locale = 'no'): string | null {
  const dateStr = formatDate(date);
  // Map locale to the underlying Norwegian holiday dataset (no/en)
  const holidayLocale = locale === 'en' ? 'en' : 'no';
  return getNorwegianHolidayName(dateStr, holidayLocale);
}

/**
 * Get all holidays for a specific year
 */
export function getHolidaysForYear(year: number, _locale: Locale = 'no') {
  return getNorwegianHolidays(year);
}
