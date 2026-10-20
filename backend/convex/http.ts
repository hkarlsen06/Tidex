import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";
import { httpAction } from "./_generated/server";

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

export default http;
