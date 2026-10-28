import { expect, test } from "bun:test";
import { notificationPresentation } from "../convex/lib/notificationPresentation";

test("an extension failure displays no other account's message, badge, or action", () => {
  const presentation = {
    alert: { title: "Private sender", body: "Private message" },
    badge: 7,
    sound: "tidex_notification.caf",
    category: "THREAD_MESSAGE",
    "thread-id": "private-thread",
  };
  const result = notificationPresentation(presentation);
  expect(result.aps).toEqual({ alert: { title: "Tidex" }, "mutable-content": 1 });
  expect(result.notification_presentation).toEqual(presentation);
});
