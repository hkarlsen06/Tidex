// bun test --env-file=.env.local ./scripts/monitoring.integration.ts
import { expect, test } from "bun:test";
import { ConvexHttpClient } from "convex/browser";
import { makeFunctionReference, type PaginationResult } from "convex/server";
import { internal } from "../convex/_generated/api";
import type { Doc } from "../convex/_generated/dataModel";

const url = process.env.CONVEX_SELF_HOSTED_URL;
const adminKey = process.env.CONVEX_SELF_HOSTED_ADMIN_KEY;
if (!url || new URL(url).hostname !== "127.0.0.1" || !adminKey) {
  throw new Error("Monitoring integration checks require the local Convex deployment");
}
const admin = new ConvexHttpClient(url);
admin.setAdminAuth(adminKey);
const anonymous = new ConvexHttpClient(url, { logger: false });

test("the exporter returns only the fixed owner's iPhones from the current database", async () => {
  const table = makeFunctionReference<"query", {
    table: string; order: string; paginationOpts: { cursor: null; numItems: number };
  }, PaginationResult<Doc<"push_devices">>>("_system/cli/tableData");
  const data = await admin.query(table, {
    table: "push_devices", order: "asc", paginationOpts: { cursor: null, numItems: 10000 },
  });
  expect(data.isDone).toBe(true);
  const owner = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
  const foreign = data.page.filter((device) => device.user_id !== owner && device.apns_token);
  expect(foreign.length).toBeGreaterThan(0);
  const snapshot = await admin.function(internal.monitoring.uptimeDevices, undefined, {});
  expect(snapshot.owner_id).toBe(owner);
  expect(snapshot.source).toBe("convex");
  expect(Date.now() - Date.parse(snapshot.exported_at)).toBeLessThan(10000);
  const eligible = data.page.filter((device) => device.user_id === owner && device.platform === "ios" && device.device_model === "iPhone" && device.apns_token);
  expect(snapshot.devices).toHaveLength(eligible.length);
  for (const device of snapshot.devices) {
    expect(eligible.some((row) => row.apns_token === device.token)).toBe(true);
    expect(foreign.some((row) => row.apns_token === device.token)).toBe(false);
  }
});

test("the public client cannot read private notification recipients", async () => {
  const query = makeFunctionReference<"query">("monitoring:uptimeDevices");
  await expect(anonymous.query(query, {})).rejects.toThrow();
});

test("the public health action reaches the query runtime without exposing account data", async () => {
  const response = await fetch("http://127.0.0.1:3211/health");
  expect(response.status).toBe(200);
  expect(response.headers.get("cache-control")).toBe("no-store");
  expect(await response.json()).toEqual({ ok: true });
});
