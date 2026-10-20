import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internalQuery, type MutationCtx, mutation, type QueryCtx, query } from "./_generated/server";
import { getViewer, requireViewer } from "./lib/auth";
import {
  canAccessThread,
  canPostToThread,
  counterpartOf,
  isObjectionable,
  messagePayload,
  metadataError,
  normalizeBody,
  richContentKind,
  threadSummary,
} from "./lib/messaging";
import { nextRevision } from "./lib/revision";
import { reject } from "./lib/syncWrite";
import { ensureState, requireAccess, threadById } from "./threads";

const MAX_BODY = 5000;
const MAX_ATTACHMENTS = 4;
const MAX_ATTACHMENT_BYTES = 5 * 1024 * 1024;
const ATTACHMENT_TYPES = new Set(["image/webp", "image/heic", "image/heif", "image/jpeg", "image/png"]);

async function messageById(ctx: QueryCtx, id: string) {
  return await ctx.db
    .query("messages")
    .withIndex("by_uuid", (q) => q.eq("id", id))
    .unique();
}

const newestFirst = (a: Doc<"messages">, b: Doc<"messages">) =>
  b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id);

/** Live messages older than the cursor, newest first. */
async function liveMessagesBefore(
  ctx: QueryCtx,
  threadId: string,
  before: { created_at: string; id: string } | null,
  count: number,
) {
  const out: Doc<"messages">[] = [];
  const rows = ctx.db
    .query("messages")
    .withIndex("by_thread_created_at", (q) => {
      const t = q.eq("thread_id", threadId);
      return before === null ? t : t.lte("created_at", before.created_at);
    })
    .order("desc");
  for await (const m of rows) {
    if (m.deleted_at !== undefined) continue;
    if (before !== null && m.created_at === before.created_at && m.id >= before.id) continue;
    out.push(m);
    if (out.length === count) break;
  }
  return out.sort(newestFirst);
}

async function page(
  ctx: QueryCtx,
  threadId: string,
  viewerId: string,
  limit: number | undefined,
  before: { created_at: string; id: string } | null,
) {
  const size = Math.min(Math.max(Math.floor(limit ?? 50), 1), 100);
  const rows = await liveMessagesBefore(ctx, threadId, before, size + 1);
  const pageRows = rows.slice(0, size).reverse();
  const hasMore = rows.length > size;
  return {
    messages: await Promise.all(pageRows.map((m) => messagePayload(ctx, m, viewerId))),
    has_more: hasMore,
    next_cursor:
      hasMore && pageRows[0] !== undefined
        ? { before_created_at: pageRows[0].created_at, before_message_id: pageRows[0].id }
        : null,
  };
}

/**
 * The open thread: the thread, the viewer's state, the counterpart, and the newest
 * messages. Replaces get_thread_sync_snapshot_v2. `latest_revision` is the cursor for
 * messages.changes, which catches up on edits, deletes and reactions to older messages.
 */
export const thread = query({
  args: { thread_id: v.string(), message_limit: v.optional(v.number()) },
  handler: async (ctx, { thread_id, message_limit }) => {
    const { user } = await requireViewer(ctx);
    await requireAccess(ctx, thread_id, user.id);
    const t = (await threadById(ctx, thread_id))!;
    const state = await ctx.db
      .query("thread_user_state")
      .withIndex("by_thread_user", (q) => q.eq("thread_id", thread_id).eq("user_id", user.id))
      .unique();
    const otherId = await counterpartOf(ctx, thread_id, user.id);
    const summary = await threadSummary(ctx, t, user.id);
    const latest = await ctx.db
      .query("messages")
      .withIndex("by_thread_revision", (q) => q.eq("thread_id", thread_id))
      .order("desc")
      .first();
    return {
      thread: {
        id: t.id,
        kind: t.kind,
        title: t.title ?? null,
        avatar_url: summary?.avatar_url ?? null,
        metadata: t.metadata ?? {},
        created_at: t.created_at,
      },
      viewer_state: {
        thread_id,
        user_id: user.id,
        last_read_message_id: state?.last_read_message_id ?? null,
        last_read_at: state?.last_read_at ?? null,
        unread_count: state?.unread_count ?? 0,
        muted: state?.muted ?? false,
        updated_at: state?.updated_at ?? t.created_at,
      },
      counterpart_state:
        otherId === null
          ? null
          : {
              user_id: otherId,
              display_name: summary?.counterpart_display_name ?? null,
              profile_picture_url: summary?.counterpart_profile_picture_url ?? null,
              oauth_avatar_url: summary?.counterpart_oauth_avatar_url ?? null,
            },
      ...(await page(ctx, thread_id, user.id, message_limit, null)),
      latest_revision: latest?.revision ?? 0,
    };
  },
});

/** Older messages. Replaces list_thread_messages_v2. */
export const list = query({
  args: {
    thread_id: v.string(),
    limit: v.optional(v.number()),
    before_created_at: v.optional(v.string()),
    before_message_id: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { user } = await requireViewer(ctx);
    await requireAccess(ctx, args.thread_id, user.id);
    if ((args.before_created_at === undefined) !== (args.before_message_id === undefined)) {
      reject("invalid", "Pagination cursor requires both before_created_at and before_message_id");
    }
    const before =
      args.before_created_at === undefined
        ? null
        : { created_at: args.before_created_at, id: args.before_message_id! };
    return await page(ctx, args.thread_id, user.id, args.limit, before);
  },
});

/**
 * Messages changed after `after`, oldest change first, deleted ones included. Edits,
 * deletes and reaction toggles all give a message a new revision. Replaces
 * list_thread_events_v2.
 */
export const changes = query({
  args: { thread_id: v.string(), after: v.number(), limit: v.optional(v.number()) },
  handler: async (ctx, { thread_id, after, limit }) => {
    const { user } = await requireViewer(ctx);
    await requireAccess(ctx, thread_id, user.id);
    const size = Math.min(Math.max(Math.floor(limit ?? 100), 1), 200);
    const rows = await ctx.db
      .query("messages")
      .withIndex("by_thread_revision", (q) => q.eq("thread_id", thread_id).gt("revision", after))
      .take(size);
    return {
      messages: await Promise.all(rows.map((m) => messagePayload(ctx, m, user.id))),
      cursor: rows.at(-1)?.revision ?? after,
      done: rows.length < size,
    };
  },
});

/** One message. Replaces get_message_sync_payload_v2 and get_message_payload. */
export const get = query({
  args: { message_id: v.string() },
  handler: async (ctx, { message_id }) => {
    const { user } = await requireViewer(ctx);
    const message = await messageById(ctx, message_id);
    if (message === null || !(await canAccessThread(ctx, message.thread_id, user.id))) return null;
    return await messagePayload(ctx, message, user.id);
  },
});

/** An upload URL for one image. The app posts the file there and sends the storage id. */
export const generateUploadUrl = mutation({
  args: { thread_id: v.string() },
  handler: async (ctx, { thread_id }) => {
    const { user } = await requireViewer(ctx);
    if (!(await canPostToThread(ctx, thread_id, user.id))) {
      reject("posting_not_allowed", "Posting is not allowed for this thread");
    }
    return await ctx.storage.generateUploadUrl();
  },
});

async function touchMessage(ctx: MutationCtx, message: Doc<"messages">) {
  await ctx.db.patch(message._id, { revision: await nextRevision(ctx) });
}

/** Points the thread preview at its newest live message. */
async function refreshThreadPreview(ctx: MutationCtx, threadId: string) {
  const t = (await threadById(ctx, threadId))!;
  const [latest] = await liveMessagesBefore(ctx, threadId, null, 1);
  await ctx.db.patch(t._id, {
    last_message_id: latest?.id,
    last_message_sender_id: latest?.sender_user_id,
    last_message_at: latest?.created_at ?? t.created_at,
    revision: await nextRevision(ctx),
  });
}

/**
 * Port of send_message. Resending the same client_id returns the first message, so
 * the app's outbox can retry safely.
 */
export const send = mutation({
  args: {
    thread_id: v.string(),
    client_id: v.string(),
    body: v.optional(v.string()),
    reply_to_message_id: v.optional(v.string()),
    attachments: v.optional(
      v.array(
        v.object({
          attachment_id: v.string(),
          storage_id: v.id("_storage"),
          mime_type: v.string(),
          byte_size: v.number(),
          width: v.optional(v.number()),
          height: v.optional(v.number()),
        }),
      ),
    ),
    metadata: v.optional(v.any()),
  },
  handler: async (ctx, args) => {
    const { user } = await requireViewer(ctx);
    if (!(await canPostToThread(ctx, args.thread_id, user.id))) {
      reject("posting_not_allowed", "Posting is not allowed for this thread");
    }
    if (args.reply_to_message_id !== undefined) {
      const target = await messageById(ctx, args.reply_to_message_id);
      if (target === null || target.thread_id !== args.thread_id || target.deleted_at !== undefined) {
        reject("invalid", "Reply target must exist in the same thread");
      }
    }
    const metadata = args.metadata ?? {};
    const metadataProblem = metadataError(metadata);
    if (metadataProblem !== null) reject("invalid", metadataProblem);

    const existing = await ctx.db
      .query("messages")
      .withIndex("by_thread_sender_client", (q) =>
        q.eq("thread_id", args.thread_id).eq("sender_user_id", user.id).eq("client_id", args.client_id),
      )
      .unique();
    if (existing !== null) return await messagePayload(ctx, existing, user.id);

    const body = normalizeBody(args.body);
    if (body !== undefined && [...body].length > MAX_BODY) {
      reject("invalid", "Message body exceeds the 5000 character limit");
    }
    if (isObjectionable(body)) reject("safety_filter", "Message blocked by safety filter");
    const attachments = args.attachments ?? [];
    if (body === undefined && attachments.length === 0 && richContentKind(metadata) === null) {
      reject("invalid", "A message must include text, at least one attachment, or supported rich content");
    }
    if (attachments.length > MAX_ATTACHMENTS) reject("invalid", "Too many attachments");
    for (const a of attachments) {
      if (!ATTACHMENT_TYPES.has(a.mime_type)) reject("invalid", `Unsupported attachment mime type: ${a.mime_type}`);
      const file = await ctx.db.system.get(a.storage_id);
      if (file === null) reject("invalid", "Attachment object not found");
      if (file.contentType !== a.mime_type) {
        reject("invalid", "Attachment mime type does not match stored object metadata");
      }
      if (file.size !== a.byte_size) reject("invalid", "Attachment size does not match stored object metadata");
      if (a.byte_size <= 0 || a.byte_size > MAX_ATTACHMENT_BYTES) {
        reject("invalid", "Attachment size exceeds the 5 MB limit");
      }
      if ((a.width !== undefined && a.width <= 0) || (a.height !== undefined && a.height <= 0)) {
        reject("invalid", "Attachment width and height must be positive");
      }
      // ponytail: Convex file storage has no owner. Storage ids are unguessable, so this
      // only stops one file from being attached twice. Track uploads per user if the
      // ids ever leave a thread.
      const used = await ctx.db
        .query("message_attachments")
        .withIndex("by_storage_id", (q) => q.eq("storage_id", a.storage_id))
        .first();
      if (used !== null) reject("invalid", "Attachment is already used");
    }

    const now = new Date().toISOString();
    const id = crypto.randomUUID();
    await ctx.db.insert("messages", {
      id,
      thread_id: args.thread_id,
      sender_user_id: user.id,
      message_type: "user",
      body,
      client_id: args.client_id,
      reply_to_message_id: args.reply_to_message_id,
      metadata,
      created_at: now,
      revision: await nextRevision(ctx),
    });
    for (const [index, a] of attachments.entries()) {
      await ctx.db.insert("message_attachments", {
        id: a.attachment_id,
        message_id: id,
        attachment_index: index,
        kind: "image",
        storage_id: a.storage_id,
        mime_type: a.mime_type,
        byte_size: a.byte_size,
        width: a.width,
        height: a.height,
        created_at: now,
      });
    }
    const t = (await threadById(ctx, args.thread_id))!;
    await ctx.db.patch(t._id, {
      last_message_id: id,
      last_message_sender_id: user.id,
      last_message_at: now,
      revision: await nextRevision(ctx),
    });
    // update_thread_unread_counts_on_message_insert
    const members = await ctx.db
      .query("thread_memberships")
      .withIndex("by_thread_user", (q) => q.eq("thread_id", args.thread_id))
      .collect();
    for (const m of members) {
      if (m.status !== "active" || m.user_id === user.id) continue;
      const state = await ensureState(ctx, args.thread_id, m.user_id);
      await ctx.db.patch(state._id, {
        unread_count: state.unread_count + 1,
        updated_at: now,
        revision: await nextRevision(ctx),
      });
    }
    const typing = await ctx.db
      .query("typing_indicators")
      .withIndex("by_thread_user", (q) => q.eq("thread_id", args.thread_id).eq("user_id", user.id))
      .unique();
    if (typing !== null) await ctx.db.delete(typing._id);
    // The new-message push (queue_thread_message_notification) moves to Convex with the
    // other notifications in phase 1, step 5.
    return await messagePayload(ctx, (await messageById(ctx, id))!, user.id);
  },
});

async function ownUserMessage(ctx: QueryCtx, messageId: string, userId: string, verb: string) {
  const message = await messageById(ctx, messageId);
  if (message === null) reject("not_found", "Message not found");
  await requireAccess(ctx, message.thread_id, userId);
  if (message.sender_user_id !== userId) reject("forbidden", `Only the sender can ${verb} this message`);
  if (message.message_type !== "user") reject("forbidden", `Only user messages can be ${verb}d`);
  return message;
}

/** Port of edit_message. Only text messages can be edited. */
export const edit = mutation({
  args: { message_id: v.string(), body: v.string() },
  handler: async (ctx, args) => {
    const { user } = await requireViewer(ctx);
    const message = await ownUserMessage(ctx, args.message_id, user.id, "edit");
    if (message.deleted_at !== undefined) reject("invalid", "Deleted messages cannot be edited");
    if (normalizeBody(message.body) === undefined) reject("invalid", "Only text messages can be edited");
    const body = normalizeBody(args.body);
    if (body === undefined) reject("invalid", "Message body cannot be empty");
    if ([...body].length > MAX_BODY) reject("invalid", "Message body exceeds the 5000 character limit");
    if (isObjectionable(body)) reject("safety_filter", "Message blocked by safety filter");
    if (body !== normalizeBody(message.body)) {
      await ctx.db.patch(message._id, {
        body,
        edited_at: new Date().toISOString(),
        revision: await nextRevision(ctx),
      });
    }
    return await messagePayload(ctx, (await ctx.db.get(message._id))!, user.id);
  },
});

/** Port of delete_message. Returns the thread summary, with the preview moved back. */
export const remove = mutation({
  args: { message_id: v.string() },
  handler: async (ctx, { message_id }) => {
    const { user } = await requireViewer(ctx);
    const message = await ownUserMessage(ctx, message_id, user.id, "delete");
    if (message.deleted_at !== undefined) reject("invalid", "Message is already deleted");
    const now = new Date().toISOString();
    await ctx.db.patch(message._id, { deleted_at: now, revision: await nextRevision(ctx) });

    // update_thread_unread_counts_on_message_soft_delete: members who had not read up
    // to this message lose one unread.
    const members = await ctx.db
      .query("thread_memberships")
      .withIndex("by_thread_user", (q) => q.eq("thread_id", message.thread_id))
      .collect();
    for (const m of members) {
      if (m.status !== "active" || m.user_id === user.id) continue;
      const state = await ctx.db
        .query("thread_user_state")
        .withIndex("by_thread_user", (q) => q.eq("thread_id", message.thread_id).eq("user_id", m.user_id))
        .unique();
      if (state === null) continue;
      const readMarker =
        state.last_read_message_id === undefined ? null : await messageById(ctx, state.last_read_message_id);
      const alreadyRead =
        readMarker !== null &&
        (message.created_at < readMarker.created_at ||
          (message.created_at === readMarker.created_at && message.id <= readMarker.id));
      if (alreadyRead) continue;
      await ctx.db.patch(state._id, {
        unread_count: Math.max(state.unread_count - 1, 0),
        updated_at: now,
        revision: await nextRevision(ctx),
      });
    }
    await refreshThreadPreview(ctx, message.thread_id);
    return await threadSummary(ctx, (await threadById(ctx, message.thread_id))!, user.id);
  },
});

/** Port of toggle_message_reaction, on the message or on one of its images. */
export const toggleReaction = mutation({
  args: { message_id: v.string(), emoji: v.string(), attachment_id: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { user } = await requireViewer(ctx);
    const emoji = args.emoji.trim();
    if (emoji === "" || [...emoji].length > 16) reject("invalid", "Reaction emoji is invalid");
    const message = await messageById(ctx, args.message_id);
    if (message === null || message.deleted_at !== undefined) reject("not_found", "Message not found");
    await requireAccess(ctx, message.thread_id, user.id);
    if (!(await canPostToThread(ctx, message.thread_id, user.id))) reject("forbidden", "Thread is read only");
    if (args.attachment_id !== undefined) {
      const attachment = await ctx.db
        .query("message_attachments")
        .withIndex("by_uuid", (q) => q.eq("id", args.attachment_id!))
        .unique();
      if (attachment === null || attachment.message_id !== message.id) reject("not_found", "Attachment not found");
    }
    const existing = (
      await ctx.db
        .query("message_reactions")
        .withIndex("by_message_user_emoji", (q) =>
          q.eq("message_id", message.id).eq("user_id", user.id).eq("emoji", emoji),
        )
        .collect()
    ).find((r) => r.attachment_id === args.attachment_id);
    if (existing !== undefined) {
      await ctx.db.delete(existing._id);
    } else {
      await ctx.db.insert("message_reactions", {
        id: crypto.randomUUID(),
        thread_id: message.thread_id,
        message_id: message.id,
        attachment_id: args.attachment_id,
        user_id: user.id,
        emoji,
        created_at: new Date().toISOString(),
      });
      // The reaction push (queue_message_reaction_notification) moves with the other
      // notifications in phase 1, step 5.
    }
    await touchMessage(ctx, message);
    return await messagePayload(ctx, (await ctx.db.get(message._id))!, user.id);
  },
});


/** The storage id of an attachment the caller may read, for the download route in http.ts. */
export const readableAttachment = internalQuery({
  args: { attachment_id: v.string() },
  handler: async (ctx, { attachment_id }) => {
    const viewer = await getViewer(ctx);
    if (viewer === null) return null;
    const attachment = await ctx.db
      .query("message_attachments")
      .withIndex("by_uuid", (q) => q.eq("id", attachment_id))
      .unique();
    const message = attachment === null ? null : await messageById(ctx, attachment.message_id);
    if (message === null || !(await canAccessThread(ctx, message.thread_id, viewer.user.id))) return null;
    return attachment!.storage_id;
  },
});
