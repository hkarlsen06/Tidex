import { createLocalJWKSet, errors, type JSONWebKeySet, jwtVerify } from "jose";

// OAuth access tokens that Clerk issues for the MCP server. The app's Convex session
// tokens come from the same issuer and keys but carry aud "convex", no client_id and no
// at+jwt type (RFC 9068), so each of those checks keeps them out.

const TOKEN_ERRORS = [
  errors.JWTExpired,
  errors.JWTInvalid,
  errors.JWTClaimValidationFailed,
  errors.JWSInvalid,
  errors.JWSSignatureVerificationFailed,
  errors.JOSEAlgNotAllowed,
  errors.JWKSNoMatchingKey,
  errors.JWKSMultipleMatchingKeys,
];

/**
 * Clerk's signing keys. `refresh` asks for a fresh copy because the token names a key the
 * cached copy lacks; the caller decides how often that may reach Clerk.
 */
export type KeySource = (refresh: boolean) => Promise<JSONWebKeySet>;

async function verify(token: string, keys: JSONWebKeySet, issuer: string, audience: string) {
  const { payload } = await jwtVerify(token, createLocalJWKSet(keys), {
    issuer,
    audience,
    algorithms: ["RS256"],
    typ: "at+jwt",
    requiredClaims: ["exp", "sub"],
    clockTolerance: 30,
  });
  // jose accepts an aud array that contains the audience; only this resource is allowed.
  if (payload.aud !== audience || typeof payload.client_id !== "string" || typeof payload.sub !== "string") return null;
  return payload.sub;
}

/** The Clerk user ID the token was issued for, or null when the token isn't valid for `audience`. */
export async function verifyAccessToken(
  token: string,
  issuer: string,
  audience: string,
  keySource: KeySource,
): Promise<string | null> {
  try {
    try {
      return await verify(token, await keySource(false), issuer, audience);
    } catch (error) {
      // Clerk may have rotated its keys since they were cached.
      if (!(error instanceof errors.JWKSNoMatchingKey)) throw error;
      return await verify(token, await keySource(true), issuer, audience);
    }
  } catch (error) {
    // A bad token is a 401. Clerk's key endpoint failing is not the token's fault, so
    // those errors reach the caller's 503.
    if (TOKEN_ERRORS.some((type) => error instanceof type)) return null;
    throw error;
  }
}
