import { createLocalJWKSet, errors, type JSONWebKeySet, jwtVerify } from "jose";

// OAuth access tokens that Clerk issues for the MCP server. The app's Convex session
// tokens come from the same issuer and keys but carry aud "convex", no client_id and no
// at+jwt type (RFC 9068), so each of those checks keeps them out.

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

/**
 * The Clerk user ID the token was issued for, or null when the token isn't valid for
 * `audience`. An error from `keySource` propagates, so a Clerk outage isn't reported as a
 * bad token.
 */
export async function verifyAccessToken(
  token: string,
  issuer: string,
  audience: string,
  keySource: KeySource,
): Promise<string | null> {
  try {
    return await verify(token, await keySource(false), issuer, audience);
  } catch (error) {
    if (!(error instanceof errors.JOSEError)) throw error;
    if (!(error instanceof errors.JWKSNoMatchingKey)) return null;
  }
  // Clerk may have rotated its keys since they were stored.
  const fresh = await keySource(true);
  try {
    return await verify(token, fresh, issuer, audience);
  } catch (error) {
    if (error instanceof errors.JOSEError) return null;
    throw error;
  }
}
