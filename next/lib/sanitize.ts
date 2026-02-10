/**
 * Sanitize user-provided strings to prevent potential XSS or injection attacks
 *
 * While React auto-escapes in JSX contexts, this provides defense-in-depth
 * for cases where data might be used in non-React contexts or serialized.
 */

/**
 * Sanitize a string by removing potentially dangerous characters
 * Allows alphanumeric, spaces, and common safe punctuation
 */
export function sanitizeUserInput(input: string | null | undefined): string {
  if (!input) return "";

  // Remove control characters and normalize whitespace
  let sanitized = input
    // eslint-disable-next-line no-control-regex -- intentionally strip control characters
    .replace(/[\u0000-\u001F\u007F-\u009F]/g, "") // Remove control characters
    .replace(/\s+/g, " ") // Normalize whitespace
    .trim();

  // Limit length to prevent abuse
  if (sanitized.length > 200) {
    sanitized = sanitized.substring(0, 200);
  }

  return sanitized;
}

/**
 * Sanitize display name (more restrictive)
 * Used for names that will be displayed prominently
 */
export function sanitizeDisplayName(name: string | null | undefined): string {
  if (!name) return "User";

  const sanitized = sanitizeUserInput(name);

  // Additional check: must contain at least one letter or number
  if (!/[a-zA-Z0-9]/.test(sanitized)) {
    return "User";
  }

  return sanitized;
}

/**
 * Sanitize URL from user metadata (profile pictures, etc.)
 * Ensures it's a valid HTTP(S) URL
 */
export function sanitizeUrl(url: string | null | undefined): string | null {
  if (!url) return null;

  try {
    const parsed = new URL(url);
    // Only allow https:// and http:// protocols
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
      return null;
    }
    return parsed.toString();
  } catch {
    // Invalid URL
    return null;
  }
}

/**
 * Extract and validate a redirect URL from an OAuth response object.
 * Checks both `redirect_url` and `redirect_to` fields, and ensures
 * the result is a valid HTTP(S) URL.
 */
export function extractRedirectUrl(data: unknown): string | null {
  if (!data || typeof data !== "object") {
    return null;
  }

  const record = data as Record<string, unknown>;
  const candidate =
    typeof record.redirect_url === "string"
      ? record.redirect_url
      : typeof record.redirect_to === "string"
        ? record.redirect_to
        : null;

  return sanitizeUrl(candidate);
}
