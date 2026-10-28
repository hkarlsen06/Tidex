/** iOS displays this neutral alert if it cannot run the notification extension. */
export function notificationPresentation(presentation: Record<string, unknown>) {
  return {
    aps: { alert: { title: "Tidex" }, "mutable-content": 1 },
    notification_presentation: presentation,
  };
}
