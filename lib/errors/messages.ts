/**
 * Standard error messages for server actions
 *
 * Centralizes error messages to ensure consistency across the application
 * and make it easier to implement i18n in the future.
 *
 * TODO: Consider implementing i18n for multi-language error messages
 */

export const ERRORS = {
  // Validation errors
  INVALID_DATE: "Ugyldig dato",
  INVALID_TIME: "Ugyldig tid",
  INVALID_SHIFT_ID: "Ugyldig skift-ID",
  INVALID_SERIES_ID: "Ugyldig serie-ID",

  // Not found errors
  SHIFT_NOT_FOUND: "Fant ikke skiftet",
  SERIES_NOT_FOUND: "Fant ikke serien",
  SETTINGS_NOT_FOUND: "Kunne ikke hente innstillinger",

  // Authorization errors
  UNAUTHORIZED: "Ikke autorisert",

  // Database errors
  DB_ERROR: "Databasefeil",

  // Wage snapshot errors
  WAGE_SNAPSHOT_CONFLICT: "En lønnsoppføring eksisterer allerede for denne datoen",
  WAGE_SNAPSHOT_NOT_FOUND: "Fant ikke lønnsoppføringen",
} as const;

export type ErrorMessage = (typeof ERRORS)[keyof typeof ERRORS];
