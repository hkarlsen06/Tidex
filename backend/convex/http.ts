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

export default http;
