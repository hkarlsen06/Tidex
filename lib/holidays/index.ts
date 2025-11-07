import Holidays from 'date-holidays';
import type { Locale } from '@/lib/i18n';

// Initialize holiday instances for supported locales
// All locales use Norwegian holidays since this is a Norwegian payroll app
const holidaysByLocale: Record<Locale, Holidays> = {
  no: new Holidays('NO'),
  en: new Holidays('NO'),
  de: new Holidays('NO'),
};

/**
 * Check if a given date is a public holiday in Norway
 */
export function isPublicHoliday(date: Date, locale: Locale = 'no'): boolean {
  const hd = holidaysByLocale[locale];
  const holiday = hd.isHoliday(date);
  return holiday !== false;
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
  const hd = holidaysByLocale[locale];
  const holiday = hd.isHoliday(date);

  if (holiday && typeof holiday === 'object' && 'name' in holiday) {
    return String(holiday.name);
  }

  return null;
}

/**
 * Get all holidays for a specific year
 */
export function getHolidaysForYear(year: number, locale: Locale = 'no') {
  return holidaysByLocale[locale].getHolidays(year);
}
