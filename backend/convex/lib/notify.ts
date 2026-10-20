import { internal } from "../_generated/api";
import type { Doc } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { userByUuid } from "./auth";

// Pushes waiting in notifications_outbox. Each function here ports one Postgres
// trigger or RPC that queued a push, with the same titles, bodies, payloads and
// idempotency keys. push.ts sends them. Queueing schedules the sender for when the
// row is due, and a cron every minute catches anything a schedule missed.

export const isNorwegian = (locale: string | undefined) => /^(no|nb|nn)([-_]|$)/i.test(locale ?? "en");

/** The name and avatar a push shows for a user, as the SQL picked them. */
export async function sender(ctx: MutationCtx, userId: string) {
  const user = await userByUuid(ctx, userId);
  const settings = await ctx.db
    .query("user_settings")
    .withIndex("by_user_revision", (q) => q.eq("user_id", userId))
    .unique();
  const picture =
    settings?.profile_picture_storage_id === undefined
      ? null
      : await ctx.storage.getUrl(settings.profile_picture_storage_id);
  return {
    user,
    name: user?.name ?? user?.email ?? "Someone",
    avatarUrl: picture ?? user?.avatar_url ?? null,
  };
}

async function admins(ctx: MutationCtx) {
  return await ctx.db
    .query("users")
    .withIndex("by_role", (q) => q.eq("role", "admin"))
    .collect();
}

type Push = {
  owner_id?: string;
  recipient_id: string;
  notification_type: string;
  thread_id?: string;
  broadcast_id?: string;
  title: string;
  body: string;
  data_payload: Record<string, unknown>;
  idempotency_key: string;
  due_at?: string;
};

/** Queues a push unless one with the same idempotency key exists. */
export async function enqueue(ctx: MutationCtx, push: Push) {
  const existing = await ctx.db
    .query("notifications_outbox")
    .withIndex("by_idempotency_key", (q) => q.eq("idempotency_key", push.idempotency_key))
    .first();
  if (existing !== null) return;
  const now = new Date().toISOString();
  const dueAt = push.due_at ?? now;
  await ctx.db.insert("notifications_outbox", {
    id: crypto.randomUUID(),
    ...push,
    status: "pending",
    due_at: dueAt,
    attempts: 0,
    created_at: now,
    updated_at: now,
  });
  await scheduleSender(ctx, dueAt);
}

export async function scheduleSender(ctx: MutationCtx, dueAt: string) {
  await ctx.scheduler.runAt(new Date(Math.max(Date.parse(dueAt), Date.now())), internal.push.run, {});
}

// ---- Messaging ----

/** queue_thread_message_notification, run after `send` has bumped the unread counts. */
export async function queueThreadMessage(ctx: MutationCtx, message: Doc<"messages">, threadKind: string) {
  const from = await sender(ctx, message.sender_user_id);
  const preview = (message.body ?? "").replace(/\s+/g, " ").slice(0, 120) || undefined;
  const richKind = (message.metadata?.content?.kind ?? "").trim();
  const members = await ctx.db
    .query("thread_memberships")
    .withIndex("by_thread_user", (q) => q.eq("thread_id", message.thread_id))
    .collect();
  const now = new Date().toISOString();
  for (const m of members) {
    if (m.status !== "active" || m.user_id === message.sender_user_id) continue;
    const state = await ctx.db
      .query("thread_user_state")
      .withIndex("by_thread_user", (q) => q.eq("thread_id", message.thread_id).eq("user_id", m.user_id))
      .unique();
    if (state?.muted) continue;
    const locale = (await userByUuid(ctx, m.user_id))?.locale;
    const no = isNorwegian(locale);

    // A real message replaces a pending typing push.
    for (const typing of await ctx.db
      .query("notifications_outbox")
      .withIndex("by_recipient_type_thread", (q) =>
        q.eq("recipient_id", m.user_id).eq("notification_type", "thread_typing").eq("thread_id", message.thread_id),
      )
      .collect()) {
      if (typing.status !== "pending" && typing.status !== "sending") continue;
      await ctx.db.patch(typing._id, {
        status: "skipped",
        error_message: "Superseded by a real thread message",
        processed_at: now,
        updated_at: now,
      });
    }

    const count = Math.max(state?.unread_count ?? 0, 1);
    const single =
      preview ??
      (richKind === "shift_snapshot"
        ? no
          ? `${from.name} delte en vakt`
          : `${from.name} shared a shift`
        : no
          ? "Sendte et bilde"
          : "Sent a photo");
    const fields = {
      owner_id: message.sender_user_id,
      title: from.name,
      body: count >= 4 ? (no ? `${count} nye meldinger` : `${count} new messages`) : single,
      data_payload: {
        type: "thread_message",
        thread_id: message.thread_id,
        message_id: message.id,
        thread_kind: threadKind,
        sender_user_id: message.sender_user_id,
        sender_name: from.name,
        sender_avatar_url: from.avatarUrl,
        message_count: count,
        message_created_at: message.created_at,
      },
    };
    // One pending push per recipient and thread, updated as messages arrive.
    const pending = (
      await ctx.db
        .query("notifications_outbox")
        .withIndex("by_recipient_type_thread", (q) =>
          q.eq("recipient_id", m.user_id).eq("notification_type", "thread_message").eq("thread_id", message.thread_id),
        )
        .collect()
    ).filter((n) => n.status === "pending");
    if (pending.length > 0) {
      for (const n of pending) await ctx.db.patch(n._id, { ...fields, due_at: now, updated_at: now });
      await scheduleSender(ctx, now);
    } else {
      await enqueue(ctx, {
        ...fields,
        recipient_id: m.user_id,
        notification_type: "thread_message",
        thread_id: message.thread_id,
        idempotency_key: `thread_message:${message.id}:${m.user_id}`,
      });
    }
  }
}

/** queue_message_reaction_notification. Direct threads only, to the message's sender. */
export async function queueReaction(ctx: MutationCtx, reaction: Doc<"message_reactions">) {
  const message = await ctx.db
    .query("messages")
    .withIndex("by_uuid", (q) => q.eq("id", reaction.message_id))
    .unique();
  if (message === null || message.deleted_at !== undefined || message.sender_user_id === reaction.user_id) return;
  const thread = await ctx.db
    .query("threads")
    .withIndex("by_uuid", (q) => q.eq("id", reaction.thread_id))
    .unique();
  if (thread?.kind !== "direct") return;
  const member = await ctx.db
    .query("thread_memberships")
    .withIndex("by_thread_user", (q) => q.eq("thread_id", reaction.thread_id).eq("user_id", message.sender_user_id))
    .unique();
  if (member?.status !== "active") return;
  const state = await ctx.db
    .query("thread_user_state")
    .withIndex("by_thread_user", (q) => q.eq("thread_id", reaction.thread_id).eq("user_id", message.sender_user_id))
    .unique();
  if (state?.muted) return;
  const from = await sender(ctx, reaction.user_id);
  const no = isNorwegian((await userByUuid(ctx, message.sender_user_id))?.locale);
  const emojiHex = [...new TextEncoder().encode(reaction.emoji)].map((b) => b.toString(16).padStart(2, "0")).join("");
  await enqueue(ctx, {
    owner_id: reaction.user_id,
    recipient_id: message.sender_user_id,
    notification_type: "thread_reaction",
    thread_id: reaction.thread_id,
    title: from.name,
    body: no ? `Reagerte ${reaction.emoji} på meldingen din` : `Reacted ${reaction.emoji} to your message`,
    data_payload: {
      type: "thread_reaction",
      thread_id: reaction.thread_id,
      thread_kind: "direct",
      message_id: reaction.message_id,
      sender_user_id: reaction.user_id,
      sender_name: from.name,
      sender_avatar_url: from.avatarUrl,
      reaction_emoji: reaction.emoji,
      message_created_at: message.created_at,
    },
    idempotency_key: `thread_reaction:${reaction.message_id}:${reaction.user_id}:${reaction.created_at}:${emojiHex}`,
  });
}

/**
 * queue_thread_typing_notification. Pushes "is typing" only when the recipient is
 * caught up, hasn't read in the last 30 seconds, and got no typing push in 2 minutes.
 */
export async function queueTyping(ctx: MutationCtx, threadId: string, senderId: string) {
  const thread = await ctx.db
    .query("threads")
    .withIndex("by_uuid", (q) => q.eq("id", threadId))
    .unique();
  if (thread?.kind !== "direct") return false;
  const recipient = (
    await ctx.db
      .query("thread_memberships")
      .withIndex("by_thread_user", (q) => q.eq("thread_id", threadId))
      .collect()
  ).find((m) => m.status === "active" && m.user_id !== senderId);
  if (recipient === undefined) return false;
  const state = await ctx.db
    .query("thread_user_state")
    .withIndex("by_thread_user", (q) => q.eq("thread_id", threadId).eq("user_id", recipient.user_id))
    .unique();
  const now = Date.now();
  if (state?.muted) return false;
  if (state?.last_read_at !== undefined && Date.parse(state.last_read_at) >= now - 30_000) return false;
  if ((state?.unread_count ?? 0) > 0) return false;
  const recent = (
    await ctx.db
      .query("notifications_outbox")
      .withIndex("by_recipient_type_thread", (q) =>
        q.eq("recipient_id", recipient.user_id).eq("notification_type", "thread_typing").eq("thread_id", threadId),
      )
      .collect()
  ).some(
    (n) =>
      n.status === "pending" ||
      n.status === "sending" ||
      ((n.status === "sent" || n.status === "skipped") && Date.parse(n.created_at) >= now - 120_000),
  );
  if (recent) return false;
  const from = await sender(ctx, senderId);
  const no = isNorwegian((await userByUuid(ctx, recipient.user_id))?.locale);
  await enqueue(ctx, {
    owner_id: senderId,
    recipient_id: recipient.user_id,
    notification_type: "thread_typing",
    thread_id: threadId,
    title: from.name,
    body: no ? "skriver..." : "is typing...",
    data_payload: {
      type: "thread_typing",
      thread_id: threadId,
      thread_kind: "direct",
      sender_user_id: senderId,
      sender_name: from.name,
      sender_avatar_url: from.avatarUrl,
    },
    idempotency_key: `thread_typing:${threadId}:${recipient.user_id}:${crypto.randomUUID()}`,
  });
  return true;
}

// ---- Sharing ----

/** queue_share_started_notification. */
export async function queueShareStarted(ctx: MutationCtx, ownerId: string, viewerId: string) {
  const prefs = await ctx.db
    .query("notification_preferences")
    .withIndex("by_user_revision", (q) => q.eq("user_id", viewerId))
    .unique();
  if (prefs?.shared_shifts_enabled === false) return;
  const from = await sender(ctx, ownerId);
  const no = isNorwegian((await userByUuid(ctx, viewerId))?.locale);
  await enqueue(ctx, {
    owner_id: ownerId,
    recipient_id: viewerId,
    notification_type: "share_started",
    title: no ? `${from.name} deler vakter med deg` : `${from.name} is sharing shifts with you`,
    body: no ? `Trykk for å se ${from.name} sine vakter` : `Tap to see ${from.name}'s shifts`,
    data_payload: { type: "share_started", owner_id: ownerId, owner_name: from.name },
    idempotency_key: `share_started:${ownerId}:${viewerId}`,
  });
}

const shiftTemplates: Record<string, [string, string]> = {
  ar: ["أضاف وردية", "أضاف %s ورديات"],
  bg: ["Добави смяна", "Добави %s смени"],
  bn: ["একটি শিফট যোগ করেছেন", "%sটি শিফট যোগ করেছেন"],
  ca: ["Ha afegit un torn", "Ha afegit %s torns"],
  cs: ["Přidal(a) směnu", "Přidal(a) %s směn"],
  da: ["Tilføjede en vagt", "Tilføjede %s vagter"],
  de: ["Hat eine Schicht hinzugefügt", "Hat %s Schichten hinzugefügt"],
  el: ["Πρόσθεσε μια βάρδια", "Πρόσθεσε %s βάρδιες"],
  en: ["Added a shift", "Added %s shifts"],
  es: ["Añadió un turno", "Añadió %s turnos"],
  et: ["Lisas vahetuse", "Lisas %s vahetust"],
  fa: ["یک شیفت اضافه کرد", "%s شیفت اضافه کرد"],
  fi: ["Lisäsi vuoron", "Lisäsi %s vuoroa"],
  fil: ["Nagdagdag ng shift", "Nagdagdag ng %s shift"],
  fr: ["A ajouté un service", "A ajouté %s services"],
  he: ["הוסיף משמרת", "הוסיף %s משמרות"],
  hi: ["एक शिफ्ट जोड़ी", "%s शिफ्ट जोड़ीं"],
  hr: ["Dodao/la je smjenu", "Dodao/la je %s smjena"],
  hu: ["Hozzáadott egy műszakot", "Hozzáadott %s műszakot"],
  id: ["Menambahkan satu shift", "Menambahkan %s shift"],
  is: ["Bætti við vakt", "Bætti við %s vöktum"],
  it: ["Ha aggiunto un turno", "Ha aggiunto %s turni"],
  ja: ["シフトを追加しました", "%s件のシフトを追加しました"],
  ko: ["근무를 추가했습니다", "근무 %s개를 추가했습니다"],
  lt: ["Pridėjo pamainą", "Pridėjo %s pamainas"],
  lv: ["Pievienoja maiņu", "Pievienoja %s maiņas"],
  nb: ["La til en vakt", "La til %s vakter"],
  nl: ["Heeft een dienst toegevoegd", "Heeft %s diensten toegevoegd"],
  nn: ["La til ei vakt", "La til %s vakter"],
  pl: ["Dodał(a) zmianę", "Dodał(a) %s zmian"],
  pt: ["Adicionou um turno", "Adicionou %s turnos"],
  "pt-br": ["Adicionou um turno", "Adicionou %s turnos"],
  ro: ["A adăugat o tură", "A adăugat %s ture"],
  ru: ["Добавил(а) смену", "Добавил(а) %s смен"],
  sk: ["Pridal(a) zmenu", "Pridal(a) %s zmien"],
  sl: ["Dodal(a) je izmeno", "Dodal(a) je %s izmen"],
  sr: ["Dodao/la je smenu", "Dodao/la je %s smena"],
  sv: ["Lade till ett pass", "Lade till %s pass"],
  sw: ["Ameongeza zamu", "Ameongeza zamu %s"],
  ta: ["ஒரு ஷிப்டைச் சேர்த்தார்", "%s ஷிப்ட்களைச் சேர்த்தார்"],
  th: ["เพิ่มกะทำงาน", "เพิ่มกะทำงาน %s กะ"],
  tr: ["Bir vardiya ekledi", "%s vardiya ekledi"],
  uk: ["Додав(ла) зміну", "Додав(ла) %s змін"],
  ur: ["ایک شفٹ شامل کی", "%s شفٹیں شامل کیں"],
  vi: ["Đã thêm một ca làm", "Đã thêm %s ca làm"],
  zh: ["添加了一个班次", "添加了 %s 个班次"],
  "zh-hans": ["添加了一个班次", "添加了 %s 个班次"],
  "zh-hant": ["新增了一個班次", "新增了 %s 個班次"],
};

/** internal.shared_shift_added_notification_body */
export function shiftAddedBody(locale: string | undefined, count: number) {
  const normalized = (locale ?? "en").replaceAll("_", "-").toLowerCase();
  const base = normalized.split("-")[0]!;
  let language = normalized.startsWith("pt-br")
    ? "pt-br"
    : normalized.startsWith("zh-hans")
      ? "zh-hans"
      : normalized.startsWith("zh-hant")
        ? "zh-hant"
        : base === "no"
          ? "nb"
          : base;
  if (!(language in shiftTemplates)) language = "en";
  const [singular, plural] = shiftTemplates[language]!;
  const n = Math.max(count, 1);
  return n === 1 ? singular : plural.replace("%s", String(n));
}

type ShiftChange = { shift_id: string; date: string; op: "added" };
const byDateThenId = (a: ShiftChange, b: ShiftChange) =>
  a.date.localeCompare(b.date) || a.shift_id.localeCompare(b.shift_id);

/** The payload fields that describe the batched shifts, as both shift triggers built them. */
function shiftBatchFields(ownerId: string, changes: ShiftChange[], count: number, extraDates: string[] = []) {
  const display = [...changes].sort(byDateThenId).slice(0, 8);
  const dates = [...new Set([...extraDates, ...changes.map((c) => c.date)])].sort().slice(0, 31);
  return {
    shift_count: count,
    total_change_count: count,
    has_more_changes: count > display.length,
    shift_dates: dates,
    changes: display,
    _internal_changes: changes,
    deeplink: `tidex://sharing?user=${ownerId}&dates=${dates.join(",")}`,
  };
}

/**
 * queue_shift_added_notification. Shifts a user adds within 90 seconds go out as one
 * push per viewer, and each new shift pushes the batch back by 90 seconds.
 */
export async function queueShiftAdded(ctx: MutationCtx, shift: Doc<"user_shifts">) {
  if (shift.deleted_at !== undefined) return;
  const from = await sender(ctx, shift.user_id);
  const shares = await ctx.db
    .query("shift_shares")
    .withIndex("by_owner_revision", (q) => q.eq("owner_id", shift.user_id))
    .collect();
  const now = new Date();
  const dueAt = new Date(now.getTime() + 90_000).toISOString();
  const pendingForOwner = (
    await ctx.db
      .query("notifications_outbox")
      .withIndex("by_owner_type_status", (q) =>
        q.eq("owner_id", shift.user_id).eq("notification_type", "shared_shift_added").eq("status", "pending"),
      )
      .collect()
  ).filter((n) => n.due_at > now.toISOString());
  for (const share of shares) {
    if (
      share.viewer_id === shift.user_id ||
      share.blocked_by_user_id !== undefined ||
      share.hidden ||
      share.muted ||
      share.owner_muted
    ) {
      continue;
    }
    const prefs = await ctx.db
      .query("notification_preferences")
      .withIndex("by_user_revision", (q) => q.eq("user_id", share.viewer_id))
      .unique();
    if (prefs?.shared_shifts_enabled === false) continue;
    const locale = (await userByUuid(ctx, share.viewer_id))?.locale;
    const change: ShiftChange = { shift_id: shift.id, date: shift.shift_date, op: "added" };
    const existing = pendingForOwner
      .filter((n) => n.recipient_id === share.viewer_id)
      .sort((a, b) => b.created_at.localeCompare(a.created_at))[0];
    const base = {
      type: "shared_shift_added",
      owner_id: shift.user_id,
      owner_name: from.name,
      sender_user_id: shift.user_id,
      sender_name: from.name,
      sender_avatar_url: from.avatarUrl,
    };
    if (existing !== undefined) {
      const payload = existing.data_payload as Record<string, unknown>;
      let changes = (payload._internal_changes ?? payload.changes ?? []) as ShiftChange[];
      const before = Math.max(
        Number(payload.total_change_count) || 0,
        Number(payload.shift_count) || 0,
        changes.length,
      );
      const duplicate = changes.some((c) => c.shift_id === shift.id);
      if (!duplicate) changes = [...changes, change];
      const count = before + (duplicate ? 0 : 1);
      await ctx.db.patch(existing._id, {
        due_at: dueAt,
        title: from.name,
        body: shiftAddedBody(locale, count),
        data_payload: { ...base, ...shiftBatchFields(shift.user_id, changes, count, (payload.shift_dates ?? []) as string[]) },
        updated_at: now.toISOString(),
      });
      await scheduleSender(ctx, dueAt);
    } else {
      await enqueue(ctx, {
        owner_id: shift.user_id,
        recipient_id: share.viewer_id,
        notification_type: "shared_shift_added",
        due_at: dueAt,
        title: from.name,
        body: shiftAddedBody(locale, 1),
        data_payload: { ...base, ...shiftBatchFields(shift.user_id, [change], 1) },
        idempotency_key: `shared_shift_added:${shift.user_id}:${share.viewer_id}:${shift.id}`,
      });
    }
  }
}

/** cancel_shift_added_notification_for_deleted_shift: takes the shift out of queued batches. */
export async function cancelShiftAdded(ctx: MutationCtx, shift: Doc<"user_shifts">) {
  const now = new Date().toISOString();
  for (const status of ["pending", "sending"] as const) {
    for (const n of await ctx.db
      .query("notifications_outbox")
      .withIndex("by_owner_type_status", (q) =>
        q.eq("owner_id", shift.user_id).eq("notification_type", "shared_shift_added").eq("status", status),
      )
      .collect()) {
      const payload = n.data_payload as Record<string, unknown>;
      const changes = (payload._internal_changes ?? payload.changes ?? []) as ShiftChange[];
      if (!changes.some((c) => c.shift_id === shift.id)) continue;
      const remaining = changes.filter((c) => c.shift_id !== shift.id).sort(byDateThenId);
      if (remaining.length === 0) {
        await ctx.db.patch(n._id, {
          status: "skipped",
          processed_at: now,
          error_message: "All queued shared shift additions were removed before delivery",
          data_payload: {
            ...payload,
            shift_count: 0,
            total_change_count: 0,
            has_more_changes: false,
            shift_dates: [],
            changes: [],
            _internal_changes: [],
          },
          updated_at: now,
        });
        continue;
      }
      const locale = (await userByUuid(ctx, n.recipient_id))?.locale;
      await ctx.db.patch(n._id, {
        body: shiftAddedBody(locale, remaining.length),
        data_payload: { ...payload, ...shiftBatchFields(shift.user_id, remaining, remaining.length) },
        updated_at: now,
      });
    }
  }
}

/** report_sharing_screenshot and report_thread_screenshot. */
export async function queueScreenshot(
  ctx: MutationCtx,
  screenshotterId: string,
  recipientId: string,
  threadId: string | undefined,
) {
  const from = await sender(ctx, screenshotterId);
  const name = from.user?.name ?? "Someone";
  const no = isNorwegian((await userByUuid(ctx, recipientId))?.locale);
  const type = threadId === undefined ? "shifts_screenshotted" : "thread_screenshot";
  const what = threadId === undefined ? (no ? "vaktene dine" : "your shifts") : no ? "chatten deres" : "your conversation";
  const epoch = Math.floor(Date.now() / 1000);
  await enqueue(ctx, {
    owner_id: screenshotterId,
    recipient_id: recipientId,
    notification_type: type,
    title: name,
    body: no ? `${name} tok et skjermbilde av ${what}` : `${name} took a screenshot of ${what}`,
    data_payload: {
      type,
      ...(threadId === undefined ? {} : { thread_id: threadId }),
      screenshotter_id: screenshotterId,
      screenshotter_name: name,
      sender_user_id: screenshotterId,
      sender_name: name,
      sender_avatar_url: from.avatarUrl,
    },
    idempotency_key:
      threadId === undefined
        ? `screenshot:${screenshotterId}:${recipientId}:${epoch}`
        : `thread_screenshot:${screenshotterId}:${threadId}:${epoch}`,
  });
}

// ---- Admin alerts ----

/** queue_feedback_submitted_notification: tells every admin. */
export async function queueFeedbackSubmitted(ctx: MutationCtx, feedback: Doc<"feedback">) {
  const author = await userByUuid(ctx, feedback.user_id);
  const name = author?.name ?? feedback.user_email;
  const preview = [...feedback.message].slice(0, 100).join("") + ([...feedback.message].length > 100 ? "..." : "");
  for (const admin of await admins(ctx)) {
    await enqueue(ctx, {
      owner_id: feedback.user_id,
      recipient_id: admin.id,
      notification_type: "feedback_submitted",
      title: "Ny tilbakemelding",
      body: `${name}: ${preview}`,
      data_payload: { type: "feedback_submitted", feedback_id: feedback.id, user_name: name, user_email: feedback.user_email },
      idempotency_key: `feedback:${feedback.id}:${admin.id}`,
    });
  }
}

/** queue_feedback_responded_notification, for when an admin first answers. */
export async function queueFeedbackResponded(ctx: MutationCtx, feedback: Doc<"feedback">) {
  if (feedback.response === undefined) return;
  const no = isNorwegian((await userByUuid(ctx, feedback.user_id))?.locale);
  const preview = [...feedback.response].slice(0, 150).join("");
  await enqueue(ctx, {
    owner_id: feedback.responded_by,
    recipient_id: feedback.user_id,
    notification_type: "feedback_responded",
    title: no ? "Svar på tilbakemeldingen din" : "Response to your feedback",
    body: preview,
    data_payload: { type: "feedback_responded", feedback_id: feedback.id, response_preview: preview },
    idempotency_key: `feedback_responded:${feedback.id}`,
  });
}

/** queue_abuse_report_notification: tells every admin. */
export async function queueAbuseReport(ctx: MutationCtx, report: Doc<"abuse_reports">) {
  const reporter = await userByUuid(ctx, report.reporter_user_id);
  const name = reporter?.name ?? reporter?.email ?? "Tidex user";
  for (const admin of await admins(ctx)) {
    await enqueue(ctx, {
      owner_id: report.reporter_user_id,
      recipient_id: admin.id,
      notification_type: "abuse_report_submitted",
      title: "Ny misbruksrapport",
      body: `${name} ${report.message_id === undefined ? "reporterte en samtale" : "rapporterte en melding"}`,
      data_payload: {
        type: "abuse_report_submitted",
        report_id: report.id,
        thread_id: report.thread_id,
        message_id: report.message_id ?? null,
        reported_user_id: report.reported_user_id,
        deeplink: `tidex://admin?tab=reports&reportId=${report.id}`,
      },
      idempotency_key: `abuse_report:${report.id}:${admin.id}`,
    });
  }
}

// Hjalmar's account, as in the Postgres trigger. Users keep their Supabase uuid.
const DIAGNOSTIC_ALERT_USER_ID = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
const quietDiagnostics = new Set(["initial_session_missing", "signed_out_received", "user_initiated_sign_out"]);

/** queue_auth_diagnostic_notification: pages the developer on warnings and errors. */
export async function queueAuthDiagnostic(ctx: MutationCtx, event: Doc<"auth_diagnostic_events">) {
  const recipient = DIAGNOSTIC_ALERT_USER_ID;
  if (quietDiagnostics.has(event.event_type)) return;
  if (event.event_type === "auth_state_changed" && event.auth_event === "signedOut") return;
  if ((event.severity !== "warning" && event.severity !== "error") || event.user_id === undefined) return;
  let body = `${event.severity} · ${event.user_id}`;
  if (event.app_version !== undefined) body += ` · v${event.app_version}`;
  if (event.error_message !== undefined) body += ` · ${event.error_message.slice(0, 120)}`;
  await enqueue(ctx, {
    owner_id: event.user_id,
    recipient_id: recipient,
    notification_type: "auth_diagnostic_event",
    title: `Tidex auth diagnostic: ${event.event_type}`,
    body,
    data_payload: {
      type: "auth_diagnostic_event",
      diagnostic_event_id: event.id,
      diagnostic_user_id: event.user_id,
      event_type: event.event_type,
      severity: event.severity,
      app_state: event.app_state ?? null,
      auth_event: event.auth_event ?? null,
      app_version: event.app_version ?? null,
      build_number: event.build_number ?? null,
      os_version: event.os_version ?? null,
      device_model: event.device_model ?? null,
      occurred_at: event.occurred_at,
      deeplink: `tidex://admin?tab=diagnostics&eventId=${event.id}`,
    },
    idempotency_key: `auth_diagnostic_event:${event.id}:${recipient}`,
  });
}
