import { deepStrictEqual as assertEquals } from "node:assert/strict";
import * as jose from "jsr:@panva/jose@6";
import { createJwtVerifier, parseJwks } from "./auth.ts";

const SECRET = "test-legacy-jwt-secret-with-enough-length";
const { publicKey, privateKey } = await jose.generateKeyPair("ES256", {
  extractable: true,
});
const jwk = { ...(await jose.exportJWK(publicKey)), kid: "k1", alg: "ES256" };
const jwks = JSON.stringify({
  keys: [jwk, { kty: "oct", k: "c2VjcmV0", alg: "HS256" }],
});
const verify = createJwtVerifier({ secret: SECRET, jwks });

function es256(claims: jose.JWTPayload, key: jose.CryptoKey = privateKey) {
  return new jose.SignJWT(claims)
    .setProtectedHeader({ alg: "ES256", kid: "k1" })
    .setExpirationTime("1h")
    .sign(key);
}

function hs256(claims: jose.JWTPayload, secret = SECRET, exp = "1h") {
  return new jose.SignJWT(claims)
    .setProtectedHeader({ alg: "HS256" })
    .setExpirationTime(exp)
    .sign(new TextEncoder().encode(secret));
}

Deno.test("accepts a GoTrue ES256 user token", async () => {
  assertEquals(await verify(await es256({ role: "authenticated" })), true);
});

Deno.test("accepts the legacy HS256 service role token", async () => {
  assertEquals(await verify(await hs256({ role: "service_role" })), true);
});

Deno.test("rejects anon tokens, which the publishable key maps to", async () => {
  assertEquals(await verify(await es256({ role: "anon" })), false);
  assertEquals(await verify(await hs256({ role: "anon" })), false);
});

Deno.test("rejects tokens without a role", async () => {
  assertEquals(await verify(await es256({})), false);
});

Deno.test("rejects the raw publishable key and garbage", async () => {
  assertEquals(await verify("sb_publishable_abc123"), false);
  assertEquals(await verify("not.a.jwt"), false);
  assertEquals(await verify(""), false);
});

Deno.test("rejects expired tokens", async () => {
  assertEquals(
    await verify(await hs256({ role: "service_role" }, SECRET, "-1m")),
    false,
  );
});

Deno.test("rejects tokens signed with an untrusted key or secret", async () => {
  const other = await jose.generateKeyPair("ES256");
  assertEquals(
    await verify(await es256({ role: "authenticated" }, other.privateKey)),
    false,
  );
  assertEquals(
    await verify(await hs256({ role: "service_role" }, "another-secret")),
    false,
  );
});

Deno.test("rejects alg none", async () => {
  const b64 = (value: object) =>
    btoa(JSON.stringify(value)).replace(/=/g, "").replace(/\+/g, "-")
      .replace(/\//g, "_");
  const token = `${b64({ alg: "none" })}.${b64({ role: "service_role" })}.`;
  assertEquals(await verify(token), false);
});

Deno.test("fails closed when no keys are configured", async () => {
  const empty = createJwtVerifier({});
  assertEquals(await empty(await es256({ role: "authenticated" })), false);
  assertEquals(await empty(await hs256({ role: "service_role" })), false);
});

Deno.test("parseJwks drops symmetric keys and bad input", () => {
  assertEquals(parseJwks(jwks)?.keys.length, 1);
  assertEquals(parseJwks("{"), null);
  assertEquals(parseJwks(undefined), null);
});
