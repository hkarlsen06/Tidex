import {
  buildApsPayload,
  coalesceNotifications,
  didAnyDeliverySucceed,
  type OutboxNotification,
  usesRichFormatting,
  usesThreadActions,
} from "./index.ts";
import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

function makeNotification(
  notificationType: string,
  overrides: Partial<OutboxNotification> = {},
): OutboxNotification {
  return {
    id: overrides.id ?? crypto.randomUUID(),
    owner_id: overrides.owner_id ?? null,
    recipient_id: overrides.recipient_id ?? "recipient-1",
    broadcast_id: overrides.broadcast_id ?? null,
    notification_type: notificationType,
    due_at: overrides.due_at ?? "2026-03-17T09:00:00.000Z",
    status: overrides.status ?? "pending",
    title: overrides.title ?? "Sender",
    body: overrides.body ?? "Hello",
    data_payload: overrides.data_payload ?? {},
    idempotency_key: overrides.idempotency_key ?? crypto.randomUUID(),
    created_at: overrides.created_at ?? "2026-03-17T09:00:00.000Z",
  };
}

Deno.test("rich-formatting helper only matches supported notification types", () => {
  assert(usesRichFormatting("thread_message"));
  assert(usesRichFormatting("thread_screenshot"));
  assert(usesRichFormatting("shifts_screenshotted"));
  assertFalse(usesRichFormatting("share_started"));
  assert(usesThreadActions("thread_message"));
  assertFalse(usesThreadActions("thread_screenshot"));
});

Deno.test("thread messages keep mutable content and thread actions", () => {
  const aps = buildApsPayload(
    makeNotification("thread_message", {
      data_payload: { thread_id: "thread-1", message_count: 2 },
    }),
    4,
  );

  assertEquals(aps["mutable-content"], 1);
  assertEquals(aps["category"], "THREAD_MESSAGE");
  assertEquals(aps["thread-id"], "thread-1");
  assertEquals(aps["target-content-id"], "friend-chat:thread-1");
});

Deno.test("rich screenshots keep mutable content without thread actions", () => {
  const aps = buildApsPayload(
    makeNotification("thread_screenshot", {
      data_payload: { thread_id: "thread-1" },
    }),
    1,
  );

  assertEquals(aps["mutable-content"], 1);
  assertFalse("category" in aps);
});

Deno.test("non-rich notifications omit mutable content", () => {
  const aps = buildApsPayload(makeNotification("share_started"), 3);

  assertFalse("mutable-content" in aps);
  assertEquals(aps["thread-id"], "sharing");
});

Deno.test("coalescing keeps all outbox rows and latest message count", () => {
  const jobs = coalesceNotifications([
    makeNotification("thread_message", {
      id: "older",
      recipient_id: "recipient-1",
      created_at: "2026-03-17T09:00:00.000Z",
      data_payload: { thread_id: "thread-1", message_count: 2 },
    }),
    makeNotification("thread_message", {
      id: "newer",
      recipient_id: "recipient-1",
      created_at: "2026-03-17T09:01:00.000Z",
      data_payload: { thread_id: "thread-1", message_count: 5 },
    }),
  ]);

  assertEquals(jobs.length, 1);
  assertEquals(jobs[0].notifications.map((notification) => notification.id), [
    "older",
    "newer",
  ]);
  assertEquals(jobs[0].notification.id, "newer");
  assertEquals(jobs[0].notification.data_payload.message_count, 5);
});

Deno.test("delivery summary succeeds when any device succeeds", () => {
  assert(didAnyDeliverySucceed([{ success: false }, { success: true }]));
  assertFalse(didAnyDeliverySucceed([{ success: false }, { success: false }]));
});
