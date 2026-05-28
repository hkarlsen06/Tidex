import {
  buildApnsEnvironmentOrder,
  buildApnsHeaders,
  buildApsPayload,
  buildPrefetchApnsHeaders,
  buildPrefetchPayload,
  coalesceNotifications,
  didAnyDeliverySucceed,
  hasDeliverableNotificationContent,
  type OutboxNotification,
  publicNotificationDataPayload,
  refreshDeliveryJobFromCurrentRows,
  usesMessagePrefetch,
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
  assert(usesRichFormatting("thread_typing"));
  assert(usesRichFormatting("thread_reaction"));
  assert(usesRichFormatting("thread_screenshot"));
  assert(usesRichFormatting("shifts_screenshotted"));
  assertFalse(usesRichFormatting("share_started"));
  assert(usesThreadActions("thread_message"));
  assertFalse(usesThreadActions("thread_typing"));
  assertFalse(usesThreadActions("thread_reaction"));
  assertFalse(usesThreadActions("thread_screenshot"));
  assert(usesMessagePrefetch("thread_message"));
  assert(usesMessagePrefetch("thread_reaction"));
  assert(usesMessagePrefetch("thread_screenshot"));
  assertFalse(usesMessagePrefetch("thread_typing"));
  assertFalse(usesMessagePrefetch("share_started"));
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

Deno.test("shared shift added notifications group by owner calendar", () => {
  const aps = buildApsPayload(
    makeNotification("shared_shift_added", {
      owner_id: "owner-1",
      data_payload: { owner_id: "owner-1" },
    }),
    0,
  );

  assertFalse("mutable-content" in aps);
  assertFalse("sound" in aps);
  assertEquals(aps["thread-id"], "shared-shifts:owner-1");
  assertEquals(aps["target-content-id"], "shared-calendar:owner-1");
  assertEquals(aps["interruption-level"], "active");
  assertEquals(aps["relevance-score"], 0.7);
});

Deno.test("shared shift added notifications collapse per recipient and owner", () => {
  const headers = buildApnsHeaders(
    makeNotification("shared_shift_added", {
      owner_id: "owner-1",
      recipient_id: "recipient-1",
    }),
  );

  assertEquals(headers["apns-push-type"], "alert");
  assertEquals(headers["apns-priority"], "10");
  assertEquals(
    headers["apns-collapse-id"],
    "shared-shift:owner-1",
  );
  assert("apns-expiration" in headers);

  const expiration = Number(headers["apns-expiration"]);
  assert(Number.isFinite(expiration));
  assert(expiration >= Math.floor(Date.now() / 1000));
  assert(expiration <= Math.floor(Date.now() / 1000) + 60 * 60 * 24);
});

Deno.test("public notification payload strips internal shared shift state", () => {
  const payload = publicNotificationDataPayload({
    type: "shared_shift_added",
    shift_count: 2,
    changes: [{ shift_id: "visible-shift" }],
    _internal_changes: [
      { shift_id: "visible-shift" },
      { shift_id: "hidden-shift" },
    ],
    _internal_debug: "hidden",
  });

  assertEquals(payload, {
    type: "shared_shift_added",
    shift_count: 2,
    changes: [{ shift_id: "visible-shift" }],
  });
});

Deno.test("empty internal shared shift batches are not deliverable", () => {
  assertFalse(
    hasDeliverableNotificationContent(
      makeNotification("shared_shift_added", {
        data_payload: {
          type: "shared_shift_added",
          _internal_changes: [],
        },
      }),
    ),
  );
  assert(
    hasDeliverableNotificationContent(
      makeNotification("shared_shift_added", {
        data_payload: {
          type: "shared_shift_added",
          _internal_changes: [{ shift_id: "shift-1" }],
        },
      }),
    ),
  );
  assert(hasDeliverableNotificationContent(makeNotification("share_started")));
});

Deno.test("delivery refresh uses current shared shift payload before sending", () => {
  const claimed = makeNotification("shared_shift_added", {
    id: "notification-1",
    status: "sending",
    data_payload: {
      type: "shared_shift_added",
      _internal_changes: [{ shift_id: "deleted-shift" }],
    },
  });
  const current = makeNotification("shared_shift_added", {
    id: claimed.id,
    status: "sending",
    data_payload: {
      type: "shared_shift_added",
      _internal_changes: [],
    },
  });

  const refreshed = refreshDeliveryJobFromCurrentRows(
    { notifications: [claimed], notification: claimed },
    [current],
  );

  assert(refreshed);
  assertEquals(refreshed.notification.data_payload._internal_changes, []);
  assertFalse(hasDeliverableNotificationContent(refreshed.notification));
});

Deno.test("delivery refresh drops notifications no longer sending", () => {
  const claimed = makeNotification("shared_shift_added", {
    id: "notification-1",
    status: "sending",
  });
  const skipped = makeNotification("shared_shift_added", {
    id: claimed.id,
    status: "skipped",
  });

  assertEquals(
    refreshDeliveryJobFromCurrentRows(
      { notifications: [claimed], notification: claimed },
      [skipped],
    ),
    null,
  );
});

Deno.test("thread typing notifications route to the same thread without actions", () => {
  const aps = buildApsPayload(
    makeNotification("thread_typing", {
      data_payload: { thread_id: "thread-1" },
    }),
    0,
  );

  assertEquals(aps["mutable-content"], 1);
  assertFalse("category" in aps);
  assertEquals(aps["thread-id"], "thread-1");
  assertEquals(aps["target-content-id"], "friend-chat:thread-1");
});

Deno.test("thread reaction notifications route to the same thread without actions", () => {
  const aps = buildApsPayload(
    makeNotification("thread_reaction", {
      data_payload: { thread_id: "thread-1" },
    }),
    0,
  );

  assertEquals(aps["mutable-content"], 1);
  assertFalse("category" in aps);
  assertEquals(aps["thread-id"], "thread-1");
  assertEquals(aps["target-content-id"], "friend-chat:thread-1");
});

Deno.test("thread typing notifications use collapse and short expiration headers", () => {
  const headers = buildApnsHeaders(
    makeNotification("thread_typing", {
      data_payload: { thread_id: "thread-1" },
    }),
  );

  assertEquals(headers["apns-push-type"], "alert");
  assertEquals(headers["apns-priority"], "10");
  assertEquals(headers["apns-collapse-id"], "thread-typing:thread-1");
  assert("apns-expiration" in headers);

  const expiration = Number(headers["apns-expiration"]);
  assert(Number.isFinite(expiration));
  assert(expiration >= Math.floor(Date.now() / 1000));
  assert(expiration <= Math.floor(Date.now() / 1000) + 60);
});

Deno.test("thread reaction notifications use per-thread collapse headers", () => {
  const headers = buildApnsHeaders(
    makeNotification("thread_reaction", {
      data_payload: { thread_id: "thread-1" },
    }),
  );

  assertEquals(headers["apns-push-type"], "alert");
  assertEquals(headers["apns-priority"], "10");
  assertEquals(headers["apns-collapse-id"], "thread-reaction:thread-1");
  assertFalse("apns-expiration" in headers);
});

Deno.test("prefetch payload uses background headers and includes message metadata", () => {
  const notification = makeNotification("thread_message", {
    data_payload: {
      thread_id: "thread-1",
      message_id: "message-1",
      message_created_at: "2026-03-17T09:00:00.000Z",
      sender_user_id: "sender-1",
    },
  });

  const headers = buildPrefetchApnsHeaders(notification);
  const payload = buildPrefetchPayload(notification);

  assertEquals(headers, {
    "apns-push-type": "background",
    "apns-priority": "5",
    "apns-collapse-id": "friend-prefetch:thread-1",
  });
  assertEquals(payload, {
    aps: { "content-available": 1 },
    delivery_mode: "prefetch",
    type: "thread_message",
    thread_id: "thread-1",
    message_id: "message-1",
    message_created_at: "2026-03-17T09:00:00.000Z",
    sender_user_id: "sender-1",
  });
});

Deno.test("reaction prefetch payload uses the same background channel", () => {
  const notification = makeNotification("thread_reaction", {
    data_payload: {
      thread_id: "thread-1",
      message_id: "message-1",
      message_created_at: "2026-03-17T09:00:00.000Z",
      sender_user_id: "sender-1",
    },
  });

  const headers = buildPrefetchApnsHeaders(notification);
  const payload = buildPrefetchPayload(notification);

  assertEquals(headers, {
    "apns-push-type": "background",
    "apns-priority": "5",
    "apns-collapse-id": "friend-prefetch:thread-1",
  });
  assertEquals(payload, {
    aps: { "content-available": 1 },
    delivery_mode: "prefetch",
    type: "thread_reaction",
    thread_id: "thread-1",
    message_id: "message-1",
    message_created_at: "2026-03-17T09:00:00.000Z",
    sender_user_id: "sender-1",
  });
});

Deno.test("prefetch payload omits alert fields and requires message id", () => {
  const notification = makeNotification("thread_screenshot", {
    data_payload: {
      thread_id: "thread-1",
    },
  });

  assertEquals(buildPrefetchApnsHeaders(notification), null);
  assertEquals(buildPrefetchPayload(notification), null);
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

Deno.test("coalescing keeps latest typing notification per recipient thread", () => {
  const jobs = coalesceNotifications([
    makeNotification("thread_typing", {
      id: "older",
      recipient_id: "recipient-1",
      created_at: "2026-03-17T09:00:00.000Z",
      data_payload: { thread_id: "thread-1" },
    }),
    makeNotification("thread_typing", {
      id: "newer",
      recipient_id: "recipient-1",
      created_at: "2026-03-17T09:01:00.000Z",
      data_payload: { thread_id: "thread-1" },
    }),
  ]);

  assertEquals(jobs.length, 1);
  assertEquals(jobs[0].notifications.map((notification) => notification.id), [
    "older",
    "newer",
  ]);
  assertEquals(jobs[0].notification.id, "newer");
});

Deno.test("coalescing keeps latest reaction notification per recipient thread", () => {
  const jobs = coalesceNotifications([
    makeNotification("thread_reaction", {
      id: "older",
      recipient_id: "recipient-1",
      created_at: "2026-03-17T09:00:00.000Z",
      data_payload: { thread_id: "thread-1", message_id: "message-1" },
    }),
    makeNotification("thread_reaction", {
      id: "newer",
      recipient_id: "recipient-1",
      created_at: "2026-03-17T09:01:00.000Z",
      data_payload: { thread_id: "thread-1", message_id: "message-2" },
    }),
  ]);

  assertEquals(jobs.length, 1);
  assertEquals(jobs[0].notifications.map((notification) => notification.id), [
    "older",
    "newer",
  ]);
  assertEquals(jobs[0].notification.id, "newer");
});

Deno.test("delivery summary succeeds when any device succeeds", () => {
  assert(didAnyDeliverySucceed([{ success: false }, { success: true }]));
  assertFalse(didAnyDeliverySucceed([{ success: false }, { success: false }]));
});

Deno.test("apns environment order prefers stored environment when known", () => {
  assertEquals(buildApnsEnvironmentOrder("sandbox"), [
    "sandbox",
    "production",
  ]);
  assertEquals(buildApnsEnvironmentOrder("production"), [
    "production",
    "sandbox",
  ]);
  assertEquals(buildApnsEnvironmentOrder(null), [
    "production",
    "sandbox",
  ]);
});
