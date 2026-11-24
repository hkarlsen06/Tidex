import { isObjectionable } from "../messaging";
import {
  allowOnly,
  boolean,
  date,
  destructive,
  friendRef,
  integer,
  MAX_RANGE_DAYS,
  month,
  optional,
  optionalString,
  parseDateQuery,
  readOnly,
  requiredString,
  updates,
} from "./args";
import type { ToolSpec } from "./registry";
import { ToolError } from "./shiftTimes";

// The friends and messages tools and argument parsers.

const MAX_MESSAGE_LENGTH = 5000;
/** Sends and share invitations an agent may make per rate-limit window, on top of the write cap. */
export const MAX_SENDS = 10;

const threadId = { type: "string", description: "Conversation thread_id from list_friends or get_messages." };
const limit = { type: "integer", minimum: 1, maximum: 100 };
const flag = (description: string) => ({ type: "boolean", description });
const reachesOthers = { readOnlyHint: false, destructiveHint: false, openWorldHint: true };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

function optionalLimit(value: unknown): number | undefined {
  return optional(value, (v) => integer(v, "limit", 1, 100));
}

function optionalFlag(value: unknown, field: string): boolean | undefined {
  return optional(value, (v) => boolean(v, field));
}

/** Message text as the app sends it: trimmed, 1 to 5000 characters, through the safety filter. */
export function messageText(value: unknown): string {
  if (typeof value !== "string" || value.trim() === "") throw new ToolError("text is required.");
  const text = value.trim();
  if ([...text].length > MAX_MESSAGE_LENGTH) {
    throw new ToolError(`text can be at most ${MAX_MESSAGE_LENGTH} characters. Shorten it or split it into several messages.`);
  }
  if (isObjectionable(text)) {
    throw new ToolError("Tidex's safety filter blocked this message. Rephrase it without offensive or sexual words.");
  }
  return text;
}

/** A client-made message id. The app's ids are UUIDs, and the server stores them as given. */
function clientId(value: unknown): string | undefined {
  return optional(value, (v) => {
    const id = typeof v === "string" ? v.toLowerCase() : "";
    if (!UUID.test(id)) throw new ToolError("client_id must be a UUID such as 0b6c5f8e-3f4a-4d2b-9a1e-6f0c2d7e8a91.");
    return id;
  });
}

/**
 * The inbox position after a page, as one opaque string. Keeps the time the page ended at
 * so a conversation that changes between pages cannot move the next page's start.
 */
export function conversationCursor(next: { before_last_message_at?: string | null; before_thread_id: string } | null) {
  return next === null ? null : `${next.before_last_message_at ?? ""}|${next.before_thread_id}`;
}

function parseConversationCursor(value: unknown) {
  const match = typeof value === "string" ? /^([^|]*)\|([^|]+)$/.exec(value) : null;
  if (match === null) throw new ToolError("cursor must be next_cursor from the previous get_messages page.");
  return { ...(match[1] ? { before_last_message_at: match[1] } : {}), before_thread_id: match[2]! };
}

export const listFriends = {
  definition: {
    name: "list_friends",
    title: "List friends",
    description:
      "Lists all friends who share shifts with the user or whom the user shares shifts with, including sharing settings, thread_id and unread_count. " +
      "Never returns email addresses; blocked pairs are excluded.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { title: "List friends", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, []);
    return {};
  },
} satisfies ToolSpec;

export const getFriendSchedule = {
  definition: {
    name: "get_friend_schedule",
    title: "Get friend's schedule",
    description:
      "Returns a friend's shifts for a month or date range (up to 366 days, defaults to the next 14 days). " +
      "When the friend shares earnings, includes gross pay, net pay after tax, tax deducted and paid hours per shift and in summary.",
    inputSchema: {
      type: "object",
      properties: {
        friend: friendRef,
        month,
        from: { ...date, description: "Start date (YYYY-MM-DD). Defaults to today in the friend's time zone." },
        to: { ...date, description: "End date (YYYY-MM-DD). Defaults to 13 days after from." },
      },
      required: ["friend"],
      additionalProperties: false,
    },
    annotations: { title: "Get friend's schedule", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["friend", "month", "from", "to"]);
    return {
      friend: requiredString(args.friend, "friend"),
      ...parseDateQuery(args, MAX_RANGE_DAYS),
    };
  },
} satisfies ToolSpec;

export const getMessages = {
  definition: {
    name: "get_messages",
    title: "Get messages",
    description:
      "Without friend or thread_id: lists conversations newest first with unread counts and last message. " +
      "With friend (ID, username or name) or thread_id: reads messages in that conversation oldest first. " +
      "Reading never marks messages as read; use mark_read for that.",
    inputSchema: {
      type: "object",
      properties: {
        friend: friendRef,
        thread_id: threadId,
        limit: { ...limit, description: "Max items to return (default 30)." },
        cursor: { type: "string", description: "next_cursor from the previous conversation list page." },
        before_message_id: { type: "string", description: "Read older messages before this message id." },
      },
      additionalProperties: false,
    },
    annotations: { title: "Get messages", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["friend", "thread_id", "limit", "cursor", "before_message_id"]);
    const friend = optionalString(args.friend, "friend");
    const thread = optionalString(args.thread_id, "thread_id");
    if (friend !== undefined && thread !== undefined) {
      throw new ToolError("Give either friend or thread_id, not both.");
    }
    const parsedLimit = optionalLimit(args.limit);
    const parsedCursor = optional(args.cursor, parseConversationCursor);
    const beforeMessageId = optionalString(args.before_message_id, "before_message_id");
    if (friend === undefined && thread === undefined) {
      if (beforeMessageId !== undefined) throw new ToolError("before_message_id requires friend or thread_id.");
      return { mode: "inbox" as const, limit: parsedLimit, cursor: parsedCursor };
    }
    if (parsedCursor !== undefined) throw new ToolError("Use before_message_id to paginate messages, not cursor.");
    return {
      mode: "thread" as const,
      ...(friend !== undefined ? { friend } : {}),
      ...(thread !== undefined ? { thread_id: thread } : {}),
      limit: parsedLimit,
      before_message_id: beforeMessageId,
    };
  },
} satisfies ToolSpec;

export const sendMessage = {
  definition: {
    name: "send_message",
    title: "Send message",
    description:
      "Sends a plain-text message to a friend (who gets a push notification). Pass friend (ID, username or name) or thread_id. " +
      `At most ${MAX_SENDS} messages and share invitations per 10 minutes. Confirm with the user first.`,
    inputSchema: {
      type: "object",
      properties: {
        friend: friendRef,
        thread_id: threadId,
        text: { type: "string", minLength: 1, maxLength: MAX_MESSAGE_LENGTH },
        client_id: { type: "string", format: "uuid", description: "Optional UUID for idempotent retries." },
      },
      required: ["text"],
      additionalProperties: false,
    },
    annotations: { title: "Send message", ...reachesOthers, idempotentHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["friend", "thread_id", "text", "client_id"]);
    const friend = optionalString(args.friend, "friend");
    const thread = optionalString(args.thread_id, "thread_id");
    if ((friend === undefined) === (thread === undefined)) {
      throw new ToolError("Give either friend or thread_id.");
    }
    return {
      ...(friend !== undefined ? { friend } : {}),
      ...(thread !== undefined ? { thread_id: thread } : {}),
      text: messageText(args.text),
      client_id: clientId(args.client_id),
    };
  },
} satisfies ToolSpec;

export const markRead = {
  definition: {
    name: "mark_read",
    title: "Mark conversation read",
    description: "Marks all messages in a conversation as read (sends a read receipt). Pass friend or thread_id.",
    inputSchema: {
      type: "object",
      properties: {
        friend: friendRef,
        thread_id: threadId,
      },
      additionalProperties: false,
    },
    annotations: { title: "Mark conversation read", ...updates },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["friend", "thread_id"]);
    const friend = optionalString(args.friend, "friend");
    const thread = optionalString(args.thread_id, "thread_id");
    if ((friend === undefined) === (thread === undefined)) {
      throw new ToolError("Give either friend or thread_id.");
    }
    return {
      ...(friend !== undefined ? { friend } : {}),
      ...(thread !== undefined ? { thread_id: thread } : {}),
    };
  },
} satisfies ToolSpec;

export const updateSharing = {
  definition: {
    name: "update_sharing",
    title: "Start or update shift sharing",
    description:
      "Starts sharing shifts with a Tidex user (pass username_or_email; sends a push notification and defaults show_my_earnings to false; confirm with the user first), " +
      "or updates sharing preferences with an existing friend (pass friend plus any of show_my_earnings, notify_them, hidden, notify_me).",
    inputSchema: {
      type: "object",
      properties: {
        username_or_email: { type: "string", maxLength: 254, description: "Start sharing with this Tidex username (with or without @) or verified email." },
        friend: friendRef,
        show_my_earnings: flag("Whether they can see the user's earnings."),
        notify_them: flag("Whether they get a push when the user adds shifts."),
        hidden: flag("Hide this friend's schedule from the Friends tab."),
        notify_me: flag("Whether the user gets a push when this friend adds shifts."),
      },
      additionalProperties: false,
    },
    annotations: { title: "Start or update shift sharing", ...reachesOthers, idempotentHint: true },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["username_or_email", "friend", "show_my_earnings", "notify_them", "hidden", "notify_me"]);
    const identifier = optionalString(args.username_or_email, "username_or_email", 254)?.trim();
    const friend = optionalString(args.friend, "friend");
    if ((identifier !== undefined) === (friend !== undefined)) {
      throw new ToolError("Give either username_or_email (to start sharing) or friend (to update settings).");
    }
    const showMyEarnings = optionalFlag(args.show_my_earnings, "show_my_earnings");
    const notifyThem = optionalFlag(args.notify_them, "notify_them");
    const hidden = optionalFlag(args.hidden, "hidden");
    const notifyMe = optionalFlag(args.notify_me, "notify_me");

    if (identifier !== undefined) {
      if (!identifier || identifier === "@") throw new ToolError("username_or_email is required.");
      if (notifyThem !== undefined || hidden !== undefined || notifyMe !== undefined) {
        throw new ToolError("When starting a share with username_or_email, pass only show_my_earnings.");
      }
      return { mode: "start" as const, identifier, show_earnings: showMyEarnings ?? false };
    }

    if ([showMyEarnings, notifyThem, hidden, notifyMe].every((v) => v === undefined)) {
      throw new ToolError("Give at least one of show_my_earnings, notify_them, hidden or notify_me.");
    }
    return {
      mode: "update" as const,
      friend: friend!,
      show_my_earnings: showMyEarnings,
      notify_them: notifyThem,
      hidden,
      notify_me: notifyMe,
    };
  },
} satisfies ToolSpec;

export const stopSharing = {
  definition: {
    name: "stop_sharing",
    title: "Stop sharing shifts",
    description:
      "Stops sharing the user's shifts with a friend (their share with the user, if any, stays). Confirm with the user first.",
    inputSchema: {
      type: "object",
      properties: { friend: friendRef },
      required: ["friend"],
      additionalProperties: false,
    },
    annotations: { title: "Stop sharing shifts", ...destructive, idempotentHint: true },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["friend"]);
    return { friend: requiredString(args.friend, "friend") };
  },
} satisfies ToolSpec;
