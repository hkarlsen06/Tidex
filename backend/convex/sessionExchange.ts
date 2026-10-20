import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import { action, internalQuery } from "./_generated/server";
import { createSignInToken } from "./lib/clerk";

// Phase 1, step 6. N+1 finds N's GoTrue session in the keychain, refreshes it with
// GoTrue, and sends the access token here. This checks it against GoTrue's public keys
// (GOTRUE_JWKS, so it still works after GoTrue is gone) and returns a Clerk sign-in
// ticket for that user, so people who update stay signed in.

const ISSUER = "https://api.tidex.no/auth/v1";

const fail = (code: string, message: string): never => {
  throw new ConvexError({ code, message });
};

const b64url = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(s.length / 4) * 4, "=")), (c) => c.charCodeAt(0));

/** Verifies a GoTrue ES256 access token and returns its claims. */
export async function verifyGoTrueToken(token: string): Promise<{ sub: string; session_id?: string }> {
  const parts = token.split(".");
  if (parts.length !== 3) fail("invalid_token", "Malformed token");
  const [headerPart, payloadPart, signaturePart] = parts as [string, string, string];
  let header: { alg?: string; kid?: string };
  let claims: { sub?: string; iss?: string; aud?: string | string[]; exp?: number; role?: string; is_anonymous?: boolean; session_id?: string };
  try {
    header = JSON.parse(new TextDecoder().decode(b64url(headerPart)));
    claims = JSON.parse(new TextDecoder().decode(b64url(payloadPart)));
  } catch {
    return fail("invalid_token", "Malformed token");
  }
  if (header.alg !== "ES256") fail("invalid_token", "Unsupported algorithm");
  const keys = (JSON.parse(process.env.GOTRUE_JWKS ?? '{"keys":[]}') as { keys: (JsonWebKey & { kid?: string })[] }).keys;
  const jwk = keys.find((k) => k.kid === header.kid);
  if (jwk === undefined) fail("invalid_token", "Unknown signing key");
  const key = await crypto.subtle.importKey("jwk", { kty: jwk!.kty, crv: jwk!.crv, x: jwk!.x, y: jwk!.y }, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    b64url(signaturePart),
    new TextEncoder().encode(`${headerPart}.${payloadPart}`),
  );
  if (!valid) fail("invalid_token", "Bad signature");
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (claims.iss !== ISSUER || !audiences.includes("authenticated") || claims.role !== "authenticated") {
    fail("invalid_token", "Wrong issuer, audience or role");
  }
  if (typeof claims.exp !== "number" || claims.exp * 1000 <= Date.now()) fail("invalid_token", "Token expired");
  if (claims.is_anonymous === true || typeof claims.sub !== "string") fail("invalid_token", "No user in token");
  return { sub: claims.sub!, session_id: claims.session_id };
}

export const clerkUserFor = internalQuery({
  args: { supabase_user_id: v.string(), session_id: v.optional(v.string()) },
  handler: async (ctx, { supabase_user_id, session_id }) => {
    if (session_id !== undefined) {
      const impersonation = await ctx.db
        .query("legacy_impersonation_sessions")
        .withIndex("by_auth_session_id", (q) => q.eq("auth_session_id", session_id))
        .first();
      if (impersonation !== null) return { error: "impersonation" as const, clerk_user_id: null };
    }
    const user = await ctx.db
      .query("users")
      .withIndex("by_supabase_user_id", (q) => q.eq("supabase_user_id", supabase_user_id))
      .unique();
    if (user === null) return { error: "not_found" as const, clerk_user_id: null };
    if (user.banned_at !== undefined) return { error: "banned" as const, clerk_user_id: null };
    if (user.clerk_user_id === undefined) return { error: "no_clerk_user" as const, clerk_user_id: null };
    return { error: null, clerk_user_id: user.clerk_user_id };
  },
});

/** Public, because the caller has no Clerk session yet. The GoTrue token is the proof. */
export const exchange = action({
  args: { access_token: v.string() },
  handler: async (ctx, { access_token }): Promise<{ ticket: string }> => {
    const claims = await verifyGoTrueToken(access_token);
    const target = await ctx.runQuery(internal.sessionExchange.clerkUserFor, {
      supabase_user_id: claims.sub,
      session_id: claims.session_id,
    });
    if (target.error !== null || target.clerk_user_id === null) {
      const code = target.error ?? "no_clerk_user";
      const messages = {
        impersonation: "This session belongs to an impersonation. Sign in again.",
        not_found: "No account for this session",
        banned: "This account is banned",
        no_clerk_user: "This account has no Clerk user. Sign in again.",
      };
      return fail(code, messages[code]);
    }
    return { ticket: await createSignInToken(target.clerk_user_id) };
  },
});
