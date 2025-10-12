/**
 * Phone validation and formatting utilities for Norwegian phone numbers (+47)
 * Users only input 8 digits, system automatically adds +47 prefix
 */

/**
 * Detect if input is a phone number (8 digits) or email (contains @)
 */
export function detectInputType(input: string): 'phone' | 'email' | 'unknown' {
  const trimmed = input.trim();

  // Check if it's an email (contains @)
  if (trimmed.includes('@')) {
    return 'email';
  }

  // Check if it's 8 digits (Norwegian phone)
  const digitsOnly = trimmed.replace(/\s/g, '');
  if (/^\d{8}$/.test(digitsOnly)) {
    return 'phone';
  }

  return 'unknown';
}

/**
 * Validate Norwegian phone number (must be exactly 8 digits)
 */
export function isValidNorwegianPhone(input: string): boolean {
  const digitsOnly = input.trim().replace(/\s/g, '');
  return /^\d{8}$/.test(digitsOnly);
}

/**
 * Normalize 8-digit Norwegian phone to E.164 format (+47XXXXXXXX)
 * This is the format Supabase expects
 */
export function normalizePhoneToE164(input: string): string {
  const digitsOnly = input.trim().replace(/\s/g, '');

  if (!isValidNorwegianPhone(digitsOnly)) {
    throw new Error('Invalid Norwegian phone number. Must be 8 digits.');
  }

  return `+47${digitsOnly}`;
}

/**
 * Format phone number for display (XX XXX XXX)
 * Input can be either 8 digits or E.164 format (+47XXXXXXXX)
 */
export function formatPhoneForDisplay(input: string): string {
  // Remove +47 prefix if present
  let digitsOnly = input.trim().replace(/\s/g, '');
  if (digitsOnly.startsWith('+47')) {
    digitsOnly = digitsOnly.substring(3);
  }

  if (digitsOnly.length !== 8) {
    return input; // Return as-is if not valid
  }

  // Format as XX XXX XXX
  return `${digitsOnly.substring(0, 2)} ${digitsOnly.substring(2, 5)} ${digitsOnly.substring(5, 8)}`;
}

/**
 * Strip +47 prefix from E.164 format to get 8 digits
 */
export function stripCountryCode(phone: string): string {
  const trimmed = phone.trim();
  if (trimmed.startsWith('+47')) {
    return trimmed.substring(3);
  }
  return trimmed;
}

/**
 * Validate email format
 */
export function isValidEmail(input: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(input.trim());
}
