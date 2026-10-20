import { reject, syncedTable } from "./lib/syncWrite";

const TIME = /^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/;
const END_TIME = /^(?:(?:[01][0-9]|2[0-3]):[0-5][0-9]|24:00)$/;

export const { insert, update, remove } = syncedTable("events", {
  check: async (_ctx, event) => {
    if (event.note.trim() === "") reject("invalid_row", "events_note_not_blank");
    if (event.notification_anchor_time !== undefined && !TIME.test(event.notification_anchor_time)) {
      reject("invalid_row", "events_notification_anchor_time_valid");
    }
    if (
      (event.start_time !== undefined && !TIME.test(event.start_time)) ||
      (event.end_time !== undefined && !END_TIME.test(event.end_time))
    ) {
      reject("invalid_row", "events_time_format_valid");
    }
    const timed =
      !event.is_all_day &&
      event.start_date === event.end_date &&
      event.start_time !== undefined &&
      event.end_time !== undefined &&
      event.end_time > event.start_time;
    const allDay =
      event.is_all_day &&
      event.start_time === undefined &&
      event.end_time === undefined &&
      event.end_date >= event.start_date;
    if (!timed && !allDay) reject("invalid_row", "events_shape_valid");
  },
});
