import { expect, test } from "bun:test";
import { syncClerkUser, type ClerkImportUser, type ClerkUser } from "./clerk-user-import";

function clerkFixture() {
  const users: (ClerkUser & { password_enabled: boolean; username: string | null })[] = [];
  const request = async (method: string, path: string, body?: object): Promise<unknown> => {
    if (method === "GET") {
      const externalId = new URL(`https://api.clerk.com/v1${path}`).searchParams.get("external_id");
      return users.filter((user) => user.external_id === externalId);
    }
    if (method !== "POST" || path !== "/users" || body === undefined) throw new Error("Unexpected Clerk request");
    if (!("external_id" in body) || typeof body.external_id !== "string") throw new Error("Missing external ID");
    const addresses = "email_address" in body ? body.email_address : [];
    if (!Array.isArray(addresses)) throw new Error("Invalid addresses");
    const emails = addresses.map((address: unknown, index: number) => {
      if (typeof address !== "string") throw new Error("Invalid address");
      return { id: `email_${index}`, email_address: address, verification: { status: "verified" }, linked_to: [] };
    });
    const user = {
      id: `user_${crypto.randomUUID()}`,
      external_id: body.external_id,
      email_addresses: emails,
      primary_email_address_id: emails[0]?.id ?? null,
      password_enabled: "password_digest" in body,
      username: "username" in body && typeof body.username === "string" ? body.username : null,
    };
    users.push(user);
    return user;
  };
  return { users, request };
}

const account = (): ClerkImportUser => ({
  id: crypto.randomUUID(),
  email: null,
  proven_emails: null,
  apple_subject: "apple-provider-subject",
  password_hash: null,
  created_at: "2026-09-21T20:35:10Z",
});

test("an Apple user without email gets one stable Clerk account without an invented address or password", async () => {
  const clerk = clerkFixture();
  const legacy = account();
  const id = await syncClerkUser(legacy, clerk.request, () => {});
  expect(id).toBe(clerk.users[0]?.id);
  expect(clerk.users[0]?.external_id).toBe(legacy.id);
  expect(clerk.users[0]?.email_addresses).toEqual([]);
  expect(clerk.users[0]?.password_enabled).toBe(false);
  expect(clerk.users[0]?.username).toBeTruthy();
  expect(await syncClerkUser(legacy, clerk.request, () => {})).toBe(id);
  expect(clerk.users).toHaveLength(1);
});

test("a phone-only or unconfirmed email account does not gain an imported login", async () => {
  for (const unconfirmed of [null, "unconfirmed@example.com"]) {
    const clerk = clerkFixture();
    const id = await syncClerkUser({ ...account(), apple_subject: null, email: unconfirmed }, clerk.request, () => {});
    expect(id).toBeNull();
    expect(clerk.users).toEqual([]);
  }
});

test("a verified identity address is imported without promoting the unconfirmed account address", async () => {
  const clerk = clerkFixture();
  const legacy = { ...account(), email: "unconfirmed@example.com", proven_emails: ["verified@example.com"] };
  const id = await syncClerkUser(legacy, clerk.request, () => {});
  expect(id).toBe(clerk.users[0]?.id);
  expect(clerk.users[0]?.email_addresses.map((email) => email.email_address)).toEqual(["verified@example.com"]);
  expect(clerk.users[0]?.username).toBeNull();
});

test("malformed Clerk user data cannot produce an account mapping", async () => {
  await expect(syncClerkUser(account(), async () => [{ id: "wrong-user" }], () => {})).rejects.toThrow("Invalid Clerk emails");
});
