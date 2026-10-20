import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";
import { httpAction } from "./_generated/server";
import { createFeedWindow } from "./lib/calendarFeed/date";
import { buildICalendarFeed } from "./lib/calendarFeed/ics";
import { normalizeCalendarFeedLocale } from "./lib/calendarFeed/locale";
import { projectRecurringShifts } from "./lib/calendarFeed/project";

const http = httpRouter();

/**
 * GET /attachments/<attachment id> with `Authorization: Bearer <Clerk token>`. Serves a
 * message image to members who can read its thread, and 404s for everyone else.
 */
http.route({
  pathPrefix: "/attachments/",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    const attachmentId = new URL(request.url).pathname.slice("/attachments/".length);
    const storageId = await ctx.runQuery(internal.messages.readableAttachment, {
      attachment_id: attachmentId,
    });
    const blob = storageId === null ? null : await ctx.storage.get(storageId);
    if (blob === null) return new Response("Not found", { status: 404 });
    return new Response(blob, {
      headers: { "Content-Type": blob.type, "Cache-Control": "private, max-age=86400" },
    });
  }),
});

/**
 * POST /attachments?thread_id=<uuid> with `Authorization: Bearer <Clerk token>` and the
 * image as the body. Stores it and returns `{ storageId }` for messages.send, which only
 * accepts the uploader's own files for that thread.
 */
http.route({
  path: "/attachments",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const threadId = new URL(request.url).searchParams.get("thread_id") ?? "";
    const userId = await ctx.runQuery(internal.messages.uploaderFor, { thread_id: threadId });
    if (userId === null) return new Response("Posting is not allowed for this thread", { status: 403 });
    const blob = await request.blob();
    if (blob.size === 0 || blob.size > 5 * 1024 * 1024) {
      return new Response("Attachment size exceeds the 5 MB limit", { status: 413 });
    }
    const storageId = await ctx.storage.store(blob);
    await ctx.runMutation(internal.messages.recordUpload, {
      storage_id: storageId,
      user_id: userId,
      thread_id: threadId,
    });
    return Response.json({ storageId });
  }),
});

/**
 * POST /profile-picture with `Authorization: Bearer <Clerk token>` and the image as the
 * body. Replaces the caller's profile picture and returns `{ url }`.
 */
http.route({
  path: "/profile-picture",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    if ((await ctx.auth.getUserIdentity()) === null) return new Response("Not signed in", { status: 401 });
    const blob = await request.blob();
    if (blob.size === 0 || blob.size > 5 * 1024 * 1024) {
      return new Response("Image size exceeds the 5 MB limit", { status: 413 });
    }
    if (!blob.type.startsWith("image/")) return new Response("Not an image", { status: 415 });
    const storageId = await ctx.storage.store(blob);
    const url = await ctx.runMutation(internal.userSettings.storeProfilePicture, { storage_id: storageId });
    return Response.json({ url });
  }),
});

/**
 * App Store Server Notifications V2. App Store Connect points here from cutover night.
 * Apple retries anything but a 200, which is what a failed write needs.
 */
http.route({
  path: "/apple-server-notifications",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    let signedPayload: unknown;
    try {
      signedPayload = (await request.json())?.signedPayload;
    } catch {
      signedPayload = undefined;
    }
    if (typeof signedPayload !== "string" || signedPayload === "") {
      return new Response("Missing signedPayload", { status: 400 });
    }
    const verified = await ctx.runAction(internal.appleVerify.verify, { signed_payload: signedPayload });
    if (verified === null) return new Response("Invalid notification", { status: 400 });
    try {
      const { status, body } = await ctx.runMutation(internal.appleNotifications.apply, verified);
      return Response.json(body, { status });
    } catch (error) {
      console.error("[apple-notifications] Exception:", error);
      return Response.json({ received: true, error: "Processing error" }, { status: 500 });
    }
  }),
});

/**
 * The calendar feed, ported from the calendar-feed Edge Function. The token is the last
 * path segment, with or without ".ics". Unknown and revoked tokens get an empty 404.
 */
const calendarFeed = httpAction(async (ctx, request) => {
  const requestId = crypto.randomUUID();
  const empty = (status: number) =>
    new Response(null, { status, headers: { "Cache-Control": "private, no-store", "x-calendar-feed-request-id": requestId } });
  const segment = new URL(request.url).pathname.split("/").filter(Boolean).at(-1) ?? "";
  const token = segment.endsWith(".ics") ? segment.slice(0, -4) : segment;
  if (!/^tidex_cal_[0-9a-f]{64}$/.test(token)) return empty(404);
  try {
    const subscription = await ctx.runMutation(internal.calendarFeed.resolve, { raw_token: token });
    if (subscription === null) return empty(404);
    const window = createFeedWindow(new Date());
    const data = await ctx.runQuery(internal.calendarFeed.data, {
      user_id: subscription.user_id,
      content_mode: subscription.content_mode,
      start_date: window.startDate,
      end_date: window.endDate,
    });
    const body =
      request.method === "HEAD"
        ? null
        : await buildICalendarFeed(
            data,
            projectRecurringShifts(data.recurringShifts, window, data.shifts),
            window,
            normalizeCalendarFeedLocale(subscription.locale),
          );
    return new Response(body, {
      status: 200,
      headers: {
        "Content-Type": "text/calendar; charset=utf-8",
        "Cache-Control": "private, no-store",
        "x-calendar-feed-request-id": requestId,
      },
    });
  } catch (error) {
    console.error(JSON.stringify({ scope: "calendar-feed", requestId, message: error instanceof Error ? error.message : String(error) }));
    return empty(500);
  }
});
http.route({ pathPrefix: "/calendar-feed/", method: "GET", handler: calendarFeed });

export default http;
