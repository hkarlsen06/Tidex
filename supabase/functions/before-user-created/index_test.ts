import {
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildSignupNotifications } from "./index.ts";

const payload = {
  metadata: {
    uuid: "hook-event-1",
    time: "2026-07-24T10:00:00.000Z",
    ip_address: "192.0.2.1",
    name: "before-user-created" as const,
  },
  user: {
    id: "new-user-1",
    aud: "authenticated",
    role: "authenticated",
    email: "new@example.com",
    phone: "",
    app_metadata: {
      provider: "email",
      providers: ["email"],
    },
    user_metadata: {
      full_name: "New User",
    },
    identities: [],
    created_at: "2026-07-24T10:00:00.000Z",
    updated_at: "2026-07-24T10:00:00.000Z",
    is_anonymous: false,
  },
};

Deno.test("buildSignupNotifications queues the sign-up for every admin", () => {
  const notifications = buildSignupNotifications(
    ["admin-1", "admin-2"],
    payload,
    "2026-07-24T10:00:01.000Z",
  );

  assertEquals(
    notifications.map((notification) => notification.recipient_id),
    ["admin-1", "admin-2"],
  );
  assertEquals(
    notifications.map((notification) => notification.idempotency_key),
    [
      "new-signup-new-user-1-admin-1",
      "new-signup-new-user-1-admin-2",
    ],
  );
  assertNotEquals(
    notifications[0].idempotency_key,
    notifications[1].idempotency_key,
  );
  assertEquals(notifications[0].data_payload, {
    new_user_id: "new-user-1",
    new_user_name: "New User",
    new_user_email: "new@example.com",
    new_user_phone: null,
    provider: "email",
    signup_ip: "192.0.2.1",
  });
});

Deno.test("buildSignupNotifications returns no rows when no admins exist", () => {
  assertEquals(
    buildSignupNotifications([], payload, "2026-07-24T10:00:01.000Z"),
    [],
  );
});
