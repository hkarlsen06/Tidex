/**
 * Extract the Supabase project reference from a Supabase URL.
 * Returns null if the URL is missing or cannot be parsed.
 */
export function getProjectRefFromUrl(url?: string | null): string | null {
  if (!url) {
    return null;
  }

  try {
    const hostname = new URL(url).hostname;
    const [projectRef] = hostname.split(".");
    return projectRef || null;
  } catch {
    return null;
  }
}

/**
 * Derive the cookie name prefix used by Supabase for auth tokens.
 * Format: sb-<project-ref>-auth-token
 */
export function getAuthCookiePrefixes(url?: string | null): string[] {
  const projectRef = getProjectRefFromUrl(url);
  return projectRef ? [`sb-${projectRef}-auth-token`] : [];
}
