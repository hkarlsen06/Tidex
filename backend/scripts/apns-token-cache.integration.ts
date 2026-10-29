// Run against the local backend after `convex dev --once`:
// bun --env-file=.env.local test scripts/apns-token-cache.integration.ts
import { expect, test } from "bun:test";
import { ConvexHttpClient } from "convex/browser";
import { makeFunctionReference } from "convex/server";

const url = process.env.CONVEX_SELF_HOSTED_URL;
const adminKey = process.env.CONVEX_SELF_HOSTED_ADMIN_KEY;
if (!url || new URL(url).hostname !== "127.0.0.1" || !adminKey) {
  throw new Error("This integration test requires the local Convex deployment and its admin key");
}
const admin = new ConvexHttpClient(url);
admin.setAdminAuth(adminKey);
const anonymous = new ConvexHttpClient(url, { logger: false });

const read = makeFunctionReference<"query", { key_id: string; team_id: string }, {
  token: string; expires_at: number;
} | null>("push:providerToken");
const remember = makeFunctionReference<"mutation", {
  key_id: string; team_id: string; token: string; expires_at: number;
}, string>("push:rememberProviderToken");
const key = () => ({ key_id: `integration-${crypto.randomUUID()}`, team_id: "integration" });

test("separate and concurrent sends share one provider token", async () => {
  const cacheKey = key();
  const expires_at = Date.now() + 3_600_000;
  const candidates = Array.from({ length: 8 }, (_, i) => `synthetic-token-${i}`);
  const selected = await Promise.all(candidates.map((token) =>
    admin.function(remember, undefined, { ...cacheKey, token, expires_at }),
  ));
  expect(new Set(selected).size).toBe(1);
  expect(candidates).toContain(selected[0]);
  expect(await admin.function(read, undefined, cacheKey)).toEqual({ token: selected[0], expires_at });
  expect(await admin.function(remember, undefined, {
    ...cacheKey, token: "later-action-token", expires_at: expires_at + 1000,
  })).toBe(selected[0]);
});

test("a token near expiry is replaced, and other signing keys stay separate", async () => {
  const cacheKey = key();
  await admin.function(remember, undefined, {
    ...cacheKey, token: "near-expiry", expires_at: Date.now() + 60_000,
  });
  const fresh = { ...cacheKey, token: "fresh", expires_at: Date.now() + 3_600_000 };
  expect(await admin.function(remember, undefined, fresh)).toBe("fresh");
  expect(await admin.function(remember, undefined, {
    ...fresh, ...key(), token: "other-key",
  })).toBe("other-key");
  expect(await admin.function(read, undefined, cacheKey)).toEqual({
    token: fresh.token, expires_at: fresh.expires_at,
  });
});

test("public callers cannot read or replace provider credentials", async () => {
  const cacheKey = key();
  await expect(anonymous.query(read, cacheKey)).rejects.toThrow();
  await expect(anonymous.mutation(remember, {
    ...cacheKey, token: "untrusted", expires_at: Date.now() + 3_600_000,
  })).rejects.toThrow();
  expect(await admin.function(read, undefined, cacheKey)).toBeNull();
});
