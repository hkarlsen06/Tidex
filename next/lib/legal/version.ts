import { legalNo } from '@/lib/i18n/dictionaries/legal.no';

/**
 * Get the current Terms of Service version date.
 *
 * This reads directly from the legal dictionary so there's only one place
 * to update when terms change. The Norwegian dictionary is used as the
 * canonical source (both locales should have the same date).
 */
export const CURRENT_TERMS_VERSION_DATE = legalNo.terms.lastUpdatedDate;

/**
 * Check if the user's terms acceptance is up-to-date.
 *
 * @param termsAcceptedAt - ISO date string of when user accepted terms
 * @returns true if user needs to re-accept terms (their acceptance is older than current version)
 */
export function needsTermsReAcceptance(termsAcceptedAt: string | null | undefined): boolean {
  if (!termsAcceptedAt) {
    return true;
  }

  const acceptedDate = new Date(termsAcceptedAt);
  const currentVersionDate = new Date(CURRENT_TERMS_VERSION_DATE);

  // User needs to re-accept if their acceptance date is before the current terms version
  return acceptedDate < currentVersionDate;
}

/**
 * Check if a JWT was issued after the current terms version date.
 *
 * If the JWT was issued after we last updated the terms, the claims are guaranteed
 * to reflect the user's current acceptance status (since any metadata changes would
 * have been captured in the JWT at issue time or via refreshSession after acceptance).
 *
 * This allows us to use fast getClaims() instead of slow getUser() for most users.
 *
 * @param jwtIssuedAt - Unix timestamp (seconds) from JWT 'iat' claim
 * @returns true if the JWT is fresh enough to trust for terms acceptance checks
 */
export function isJwtFreshForTermsCheck(jwtIssuedAt: number | undefined): boolean {
  if (!jwtIssuedAt) {
    return false;
  }

  const jwtIssuedDate = new Date(jwtIssuedAt * 1000);
  const termsVersionDate = new Date(CURRENT_TERMS_VERSION_DATE);

  // JWT is fresh if it was issued on or after the terms version date
  return jwtIssuedDate >= termsVersionDate;
}
