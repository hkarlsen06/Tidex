import { createLocalJWKSet, errors, importJWK, type JSONWebKeySet, jwtVerify } from "jose";

// OAuth access tokens that Clerk issues for the MCP server. The app's Convex session
// tokens come from the same issuer and keys but carry aud "convex", no client_id and no
// at+jwt type (RFC 9068), so each of those checks keeps them out.

/**
 * Clerk's signing keys. `refresh` asks for a fresh copy because the token names a key the
 * cached copy lacks; the caller decides how often that may reach Clerk.
 */
export type KeySource = (refresh: boolean) => Promise<JSONWebKeySet>;

type KeySet = ReturnType<typeof createLocalJWKSet>;

/**
 * Throws unless `keys` holds RS256 public keys that import, each with its own kid. Run on
 * what Clerk returns before it replaces stored keys, because jose imports keys only when a
 * token uses them.
 */
export async function checkKeySet(keys: unknown): Promise<JSONWebKeySet> {
  const list = (keys as JSONWebKeySet | null)?.keys;
  const usable =
    Array.isArray(list) &&
    list.length > 0 &&
    new Set(list.map((key) => key?.kid)).size === list.length &&
    list.every((key) => key?.kty === "RSA" && typeof key.kid === "string" && typeof key.n === "string" &&
      typeof key.e === "string" && key.d === undefined);
  if (!usable) throw new Error("Clerk JWKS has no usable keys");
  await Promise.all(list.map((key) => importJWK(key, "RS256")));
  return keys as JSONWebKeySet;
}

/**
 * Null for an error that means the token is bad. Rethrows the rest, including a broken key
 * set, which is Clerk's fault and not the token's.
 */
function invalidToken(error: unknown): null {
  if (error instanceof errors.JWKSInvalid || error instanceof errors.JWKSMultipleMatchingKeys) throw error;
  if (error instanceof errors.JOSEError) return null;
  throw error;
}

async function verify(token: string, keys: KeySet, issuer: string, audience: string) {
  const { payload } = await jwtVerify(token, keys, {
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
  // Built outside the try blocks: a broken key set is Clerk's fault, not the token's.
  const keys = createLocalJWKSet(await keySource(false));
  try {
    return await verify(token, keys, issuer, audience);
  } catch (error) {
    // An unknown key may be one Clerk rotated in after the keys were stored; retry below.
    if (!(error instanceof errors.JWKSNoMatchingKey)) return invalidToken(error);
  }
  const fresh = createLocalJWKSet(await keySource(true));
  try {
    return await verify(token, fresh, issuer, audience);
  } catch (error) {
    return invalidToken(error);
  }
}
