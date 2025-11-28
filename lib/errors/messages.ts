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
  INVALID_RECURRING_ID: "Ugyldig gjentakende vakt-ID",
  MIN_ONE_SHIFT_REQUIRED: "Minst én vakt er påkrevd",

  // Not found errors
  SHIFT_NOT_FOUND: "Fant ikke skiftet",
  RECURRING_NOT_FOUND: "Fant ikke gjentakende vakt",
  SETTINGS_NOT_FOUND: "Kunne ikke hente innstillinger",
  NO_SHIFTS_FOUND: "Ingen vakter funnet",

  // Authorization errors
  UNAUTHORIZED: "Ikke autorisert",

  // Database errors
  DB_ERROR: "Databasefeil",
  FAILED_TO_LOAD_RECURRING: "Kunne ikke laste gjentakende vakt",
  FAILED_TO_UPDATE_RECURRING: "Kunne ikke oppdatere gjentakende vakt",
  FAILED_TO_DELETE_RECURRING: "Kunne ikke slette gjentakende vakt",
  FAILED_TO_CREATE_SHIFT: "Kunne ikke opprette skift",

  // Wage snapshot errors
  WAGE_SNAPSHOT_CONFLICT: "En lønnsoppføring eksisterer allerede for denne datoen",
  WAGE_SNAPSHOT_NOT_FOUND: "Fant ikke lønnsoppføringen",
} as const;

export type ErrorMessage = (typeof ERRORS)[keyof typeof ERRORS];
