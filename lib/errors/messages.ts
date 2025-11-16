/**
 * Standard error messages for server actions
 *
 * Centralizes error messages to ensure consistency across the application.
 * All error messages are in Norwegian to match the primary codebase language.
 */

export const ERRORS = {
  // Validation errors
  INVALID_DATE: "Ugyldig dato",
  INVALID_TIME: "Ugyldig tid",
  INVALID_SHIFT_ID: "Ugyldig skift-ID",
  INVALID_SERIES_ID: "Ugyldig serie-ID",
  MIN_ONE_SHIFT_REQUIRED: "Minst én vakt er påkrevd",

  // Not found errors
  SHIFT_NOT_FOUND: "Fant ikke skiftet",
  SERIES_NOT_FOUND: "Fant ikke serien",
  SETTINGS_NOT_FOUND: "Kunne ikke hente innstillinger",
  NO_SHIFTS_FOUND: "Ingen vakter funnet",

  // Authorization errors
  UNAUTHORIZED: "Ikke autorisert",

  // Database errors
  DB_ERROR: "Databasefeil",
  FAILED_TO_LOAD_SERIES: "Kunne ikke laste serien",
  FAILED_TO_UPDATE_SERIES: "Kunne ikke oppdatere serien",
  FAILED_TO_DELETE_SERIES: "Kunne ikke slette serien",
  FAILED_TO_CREATE_SHIFT: "Kunne ikke opprette skift",

  // Wage snapshot errors
  WAGE_SNAPSHOT_CONFLICT: "En lønnsoppføring eksisterer allerede for denne datoen",
  WAGE_SNAPSHOT_NOT_FOUND: "Fant ikke lønnsoppføringen",
} as const;

export type ErrorMessage = (typeof ERRORS)[keyof typeof ERRORS];
