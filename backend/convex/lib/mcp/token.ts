import { createRemoteJWKSet, errors, jwtVerify } from "jose";

// OAuth access tokens that Clerk issues for the MCP server. The app's Convex session
// tokens come from the same issuer and keys but carry aud "convex", no client_id and no
// at+jwt type (RFC 9068), so each of those checks keeps them out.

const keySets = new Map<string, ReturnType<typeof createRemoteJWKSet>>();

function keysFor(issuer: string) {
  let keys = keySets.get(issuer);
  if (keys === undefined) {
    keys = createRemoteJWKSet(new URL(`${issuer}/.well-known/jwks.json`));
    keySets.set(issuer, keys);
  }
  return keys;
}

/** The Clerk user ID the token was issued for, or null when the token isn't valid for `audience`. */
export async function verifyAccessToken(token: string, issuer: string, audience: string): Promise<string | null> {
  try {
    const { payload } = await jwtVerify(token, keysFor(issuer), {
      issuer,
      audience,
      algorithms: ["RS256"],
      typ: "at+jwt",
      requiredClaims: ["exp", "sub"],
      clockTolerance: 30,
    });
    if (typeof payload.client_id !== "string" || typeof payload.sub !== "string") return null;
    return payload.sub;
  } catch (error) {
    // A bad token is a 401. Clerk being unreachable is not the token's fault.
    if (error instanceof errors.JOSEError && !(error instanceof errors.JWKSTimeout)) return null;
    throw error;
  }
}
