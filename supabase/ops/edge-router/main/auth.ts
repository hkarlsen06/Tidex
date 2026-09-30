import * as jose from "jsr:@panva/jose@6";

// Roles the gateway or GoTrue put in tokens that may call protected functions.
// The publishable key reaches functions as a role=anon JWT, so anon is not
// allowed here.
const ALLOWED_ROLES = new Set(["authenticated", "service_role"]);

// Parses the SUPABASE_JWKS env value. Symmetric (oct) keys are dropped because
// HS256 tokens are checked against JWT_SECRET instead.
export function parseJwks(raw: string | undefined): jose.JSONWebKeySet | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed?.keys)) return null;
    return {
      keys: parsed.keys.filter((key: { kty?: string }) => key?.kty !== "oct"),
    };
  } catch {
    return null;
  }
}

export function bearerToken(req: Request): string | null {
  const match = /^Bearer\s+(\S+)$/i.exec(
    req.headers.get("authorization") ?? "",
  );
  return match ? match[1] : null;
}

// Returns a function that resolves true only for an unexpired token with an
// allowed role that was signed by a key we trust:
// - HS256 with JWT_SECRET (legacy anon/service_role keys and old user tokens)
// - ES256/RS256 with the JWKS public keys (tokens GoTrue issues today)
// The algorithm list is pinned per key type so a token cannot pick its own.
export function createJwtVerifier(
  options: { secret?: string; jwks?: string },
): (token: string) => Promise<boolean> {
  const secretKey = options.secret
    ? new TextEncoder().encode(options.secret)
    : null;
  const jwks = parseJwks(options.jwks);
  const localJwks = jwks && jwks.keys.length > 0
    ? jose.createLocalJWKSet(jwks)
    : null;

  return async (token) => {
    try {
      const { alg } = jose.decodeProtectedHeader(token);
      let payload: jose.JWTPayload;
      if (alg === "HS256" && secretKey) {
        ({ payload } = await jose.jwtVerify(token, secretKey, {
          algorithms: ["HS256"],
        }));
      } else if ((alg === "ES256" || alg === "RS256") && localJwks) {
        ({ payload } = await jose.jwtVerify(token, localJwks, {
          algorithms: ["ES256", "RS256"],
        }));
      } else {
        return false;
      }
      return typeof payload.role === "string" &&
        ALLOWED_ROLES.has(payload.role);
    } catch {
      return false;
    }
  };
}
