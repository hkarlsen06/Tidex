import type { Doc } from "../_generated/dataModel";
import type { QueryCtx } from "../_generated/server";
import { userByUuid } from "./auth";

// Shared rules and payloads for messaging. Ports of can_access_thread,
// can_post_to_thread, is_user_pair_abuse_blocked, is_objectionable_text,
// message_supported_rich_content_kind, message_preview_kind, get_message_payload and
// get_thread_summary.

export async function membership(ctx: QueryCtx, threadId: string, userId: string) {
  return await ctx.db
    .query("thread_memberships")
    .withIndex("by_thread_user", (q) => q.eq("thread_id", threadId).eq("user_id", userId))
    .unique();
}

/** True when either direction of the pair's share is blocked. */
export async function pairBlocked(ctx: QueryCtx, userId: string, otherId: string) {
  if (userId === otherId) return false;
  for (const [owner, viewer] of [
    [userId, otherId],
    [otherId, userId],
  ]) {
    const share = await ctx.db
      .query("shift_shares")
      .withIndex("by_owner_viewer", (q) => q.eq("owner_id", owner).eq("viewer_id", viewer))
      .unique();
    if (share?.blocked_by_user_id !== undefined && share !== null) return true;
  }
  return false;
}

/** The other user of a direct thread, or null for other kinds. */
export async function counterpartOf(ctx: QueryCtx, threadId: string, userId: string) {
  const direct = await ctx.db
    .query("direct_threads")
    .withIndex("by_thread", (q) => q.eq("thread_id", threadId))
    .unique();
  if (direct === null) return null;
  if (direct.user_low_id === userId) return direct.user_high_id;
  if (direct.user_high_id === userId) return direct.user_low_id;
  return null;
}

export async function canAccessThread(ctx: QueryCtx, threadId: string, userId: string) {
  const member = await membership(ctx, threadId, userId);
  if (member === null || member.status !== "active") return false;
  const other = await counterpartOf(ctx, threadId, userId);
  return other === null || !(await pairBlocked(ctx, userId, other));
}

export async function canPostToThread(ctx: QueryCtx, threadId: string, userId: string) {
  const member = await membership(ctx, threadId, userId);
  if (member === null || member.status !== "active" || member.role === "reader") return false;
  const other = await counterpartOf(ctx, threadId, userId);
  return other === null || !(await pairBlocked(ctx, userId, other));
}

// ---- Content rules ----

const OBJECTIONABLE = new RegExp(
  [
    "kys",
    "kill\\s+yourself",
    "suicide",
    "selvmord",
    "ta\\s+livet\\s+ditt",
    "drep\\s+deg\\s+selv",
    "rape",
    "rapist",
    "voldtekt",
    "voldtektsmann",
    "porn",
    "pornography",
    "porno",
    "pedophile",
    "pedofil",
    "pedo",
    "nude\\s+pics?",
    "send\\s+nudes?",
    "send\\s+nakenbilder",
    "nakenbilder",
    "nigger",
    "nigga",
    "faggot",
    "homo",
    "tranny",
    "retard",
    "tilbakestaende",
    "heil\\s+hitler",
    "nazi",
    "nazist",
    "gas\\s+the\\s+jews",
    "gass\\s+jodene",
    "jodeutryddelse",
    "neger",
    "svarting",
    "pakkis",
    "jaevla\\s+utlending",
    "hore",
    "fitte",
    "kuk",
  ].join("|"),
  "i",
);

/** is_objectionable_text. Like the SQL, it matches anywhere in the text, not on word boundaries. */
export function isObjectionable(text: string | undefined): boolean {
  const normalized = (text ?? "")
    .toLowerCase()
    .replaceAll("æ", "ae")
    .replaceAll("ø", "o")
    .replaceAll("å", "a")
    .replace(/[^\p{L}\p{N}]+/gu, " ");
  return normalized.trim() !== "" && OBJECTIONABLE.test(normalized);
}

/** Trims like the SQL's regexp_replace('^\s+|\s+$'). Empty becomes undefined. */
export const normalizeBody = (body: string | undefined) => {
  const trimmed = (body ?? "").trim();
  return trimmed === "" ? undefined : trimmed;
};

const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/;
const isObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const isNonBlank = (v: unknown) => typeof v === "string" && v.trim() !== "";
const stringOrNull = (v: unknown) => v === undefined || v === null || typeof v === "string";
const numberOrNull = (v: unknown) => v === undefined || v === null || typeof v === "number";
const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;

/** message_supported_rich_content_kind: "shift_snapshot" for a valid snapshot, else null. */
export function richContentKind(metadata: unknown): "shift_snapshot" | null {
  if (!isObject(metadata) || !isObject(metadata.content)) return null;
  const content = metadata.content;
  if (typeof content.kind !== "string" || content.kind.trim() !== "shift_snapshot") return null;
  const s = content.shift_snapshot;
  if (!isObject(s)) return null;
  const date = s.shift_date;
  const ok =
    String(s.schema_version) === "1" &&
    typeof s.owner_user_id === "string" &&
    UUID.test(s.owner_user_id) &&
    isNonBlank(s.owner_display_name) &&
    stringOrNull(s.owner_avatar_url) &&
    typeof s.shift_id === "string" &&
    UUID.test(s.shift_id) &&
    stringOrNull(s.job_name) &&
    stringOrNull(s.job_color_hex) &&
    typeof date === "string" &&
    /^\d{4}-\d{2}-\d{2}$/.test(date) &&
    new Date(`${date}T00:00:00Z`).toISOString().startsWith(date) &&
    typeof s.start_time === "string" &&
    TIME.test(s.start_time) &&
    typeof s.end_time === "string" &&
    TIME.test(s.end_time) &&
    typeof s.paid_hours === "number" &&
    isNonBlank(s.currency) &&
    typeof s.includes_earnings === "boolean" &&
    numberOrNull(s.gross_pay) &&
    numberOrNull(s.net_pay) &&
    (s.includes_earnings
      ? typeof s.gross_pay === "number" && typeof s.net_pay === "number"
      : (s.gross_pay ?? null) === null && (s.net_pay ?? null) === null) &&
    typeof s.tax_enabled === "boolean" &&
    isNonBlank(s.source);
  return ok ? "shift_snapshot" : null;
}

/** assert_message_metadata_validity. Returns an error message, or null when valid. */
export function metadataError(metadata: unknown): string | null {
  if (!isObject(metadata)) return "Metadata must be a JSON object";
  if (JSON.stringify(metadata).length > 8192) return "Metadata exceeds the 8 KB limit";
  if (!("content" in metadata)) return null;
  if (!isObject(metadata.content)) return "Metadata content must be a JSON object";
  const kind = typeof metadata.content.kind === "string" ? metadata.content.kind.trim() : "";
  if (kind === "") return "Metadata content kind is required";
  if (richContentKind(metadata) !== null) return null;
  if (kind === "shift_snapshot") return "Invalid shift snapshot metadata";
  return `Unsupported rich content kind: ${kind}`;
}

export function previewKind(body: string | undefined, metadata: unknown, hasImage: boolean) {
  if (normalizeBody(body) !== undefined) return "text";
  if (hasImage) return "image";
  return richContentKind(metadata) ?? "unknown";
}

// ---- Payloads ----

type Reaction = Doc<"message_reactions">;

function reactionSummary(reactions: Reaction[], viewerId: string) {
  const groups = new Map<string, { count: number; mine: boolean; first: string }>();
  for (const r of reactions) {
    const g = groups.get(r.emoji) ?? { count: 0, mine: false, first: r.created_at };
    g.count += 1;
    g.mine ||= r.user_id === viewerId;
    if (r.created_at < g.first) g.first = r.created_at;
    groups.set(r.emoji, g);
  }
  return [...groups.entries()]
    .sort(
      ([ea, a], [eb, b]) =>
        Number(b.mine) - Number(a.mine) ||
        b.count - a.count ||
        a.first.localeCompare(b.first) ||
        ea.localeCompare(eb),
    )
    .map(([emoji, g]) => ({ emoji, count: g.count, viewer_has_reacted: g.mine }));
}

/**
 * get_message_payload, as `viewerId` sees it. Attachments carry a `url` in place of
 * storage_bucket and storage_path. It points at the HTTP action in http.ts, which
 * checks the caller's Clerk token and thread access on every download, as the
 * authenticated storage GET did.
 */
export async function messagePayload(ctx: QueryCtx, message: Doc<"messages">, viewerId: string) {
  const reactions = await ctx.db
    .query("message_reactions")
    .withIndex("by_message_user_emoji", (q) => q.eq("message_id", message.id))
    .collect();
  const attachments = await ctx.db
    .query("message_attachments")
    .withIndex("by_message", (q) => q.eq("message_id", message.id))
    .collect();
  return {
    id: message.id,
    thread_id: message.thread_id,
    sender_user_id: message.sender_user_id,
    message_type: message.message_type,
    body: message.body ?? null,
    client_id: message.client_id,
    reply_to_message_id: message.reply_to_message_id ?? null,
    created_at: message.created_at,
    edited_at: message.edited_at ?? null,
    deleted_at: message.deleted_at ?? null,
    metadata: message.metadata ?? {},
    revision: message.revision,
    attachments: await Promise.all(
      attachments.map(async (a) => ({
        id: a.id,
        attachment_index: a.attachment_index,
        kind: a.kind,
        url: `${process.env.CONVEX_SITE_URL}/attachments/${a.id}`,
        mime_type: a.mime_type,
        byte_size: a.byte_size,
        width: a.width ?? null,
        height: a.height ?? null,
        created_at: a.created_at,
        reactions: reactionSummary(
          reactions.filter((r) => r.attachment_id === a.id),
          viewerId,
        ),
      })),
    ),
    reactions: reactionSummary(
      reactions.filter((r) => r.attachment_id === undefined),
      viewerId,
    ),
  };
}

/** get_thread_summary for `viewerId`, or null when the viewer can't see the thread. */
export async function threadSummary(ctx: QueryCtx, thread: Doc<"threads">, viewerId: string) {
  const member = await membership(ctx, thread.id, viewerId);
  if (member === null || member.status !== "active") return null;
  const otherId = thread.kind === "direct" ? await counterpartOf(ctx, thread.id, viewerId) : null;
  if (otherId !== null && (await pairBlocked(ctx, viewerId, otherId))) return null;

  const state = await ctx.db
    .query("thread_user_state")
    .withIndex("by_thread_user", (q) => q.eq("thread_id", thread.id).eq("user_id", viewerId))
    .unique();
  const other = otherId === null ? null : await userByUuid(ctx, otherId);
  const otherSettings =
    otherId === null
      ? null
      : await ctx.db
          .query("user_settings")
          .withIndex("by_user_revision", (q) => q.eq("user_id", otherId))
          .unique();
  const last =
    thread.last_message_id === undefined
      ? null
      : await ctx.db
          .query("messages")
          .withIndex("by_uuid", (q) => q.eq("id", thread.last_message_id!))
          .unique();
  const lastHasImage =
    last !== null &&
    (await ctx.db
      .query("message_attachments")
      .withIndex("by_message", (q) => q.eq("message_id", last.id))
      .first()) !== null;

  return {
    thread_id: thread.id,
    kind: thread.kind,
    title: thread.title ?? null,
    avatar_url:
      thread.avatar_storage_id === undefined ? null : await ctx.storage.getUrl(thread.avatar_storage_id),
    metadata: thread.metadata ?? {},
    counterpart_user_id: otherId,
    counterpart_display_name: otherId === null ? null : (other?.name ?? other?.email ?? "Someone"),
    counterpart_profile_picture_url:
      otherSettings?.profile_picture_storage_id === undefined
        ? null
        : await ctx.storage.getUrl(otherSettings.profile_picture_storage_id),
    counterpart_oauth_avatar_url: otherId === null ? null : (other?.avatar_url ?? null),
    last_message_id: thread.last_message_id ?? null,
    last_message_sender_id: thread.last_message_sender_id ?? null,
    last_message_at: thread.last_message_at,
    last_message_body: last?.body ?? null,
    last_message_preview_kind: previewKind(last?.body, last?.metadata, lastHasImage),
    last_message_has_image: lastHasImage,
    unread_count: state?.unread_count ?? 0,
    muted: state?.muted ?? false,
    created_at: thread.created_at,
    // The app orders unread counts and mute by this, so a stale summary can't overwrite a newer one.
    viewer_state_updated_at: state?.updated_at ?? null,
  };
}
