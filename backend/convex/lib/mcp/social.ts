import { isObjectionable } from "../messaging";
import { allowOnly, optional, optionalString, requiredString } from "./args";
import type { ToolSpec } from "./registry";
import { parseRange, ToolError } from "./shiftTimes";

// The friends and messages tools and the arguments each one accepts. Arguments are
// checked here, so the Convex functions in mcpSocial.ts get well-formed values.

const MAX_RANGE_DAYS = 93;
const MAX_MESSAGE_LENGTH = 5000;
/** Sends and share invitations an agent may make per rate-limit window, on top of the write cap. */
export const MAX_SENDS = 10;

const date = { type: "string", format: "date", description: "YYYY-MM-DD" };
const friendId = { type: "string", description: "A friend_id from list_friends" };
const threadId = { type: "string", description: "A thread_id from list_conversations" };
const limit = { type: "integer", minimum: 1, maximum: 100 };
const flag = (description: string) => ({ type: "boolean", description });

const readOnly = { readOnlyHint: true, openWorldHint: false };
// Writes that reach another person: a message, a push, or a new friend.
const reachesOthers = { readOnlyHint: false, destructiveHint: false, openWorldHint: true };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

function optionalLimit(value: unknown): number | undefined {
  return optional(value, (v) => {
    if (typeof v !== "number" || !Number.isInteger(v) || v < 1 || v > 100) {
      throw new ToolError("limit must be a whole number from 1 to 100.");
    }
    return v;
  });
}

function optionalFlag(value: unknown, field: string): boolean | undefined {
  return optional(value, (v) => {
    if (typeof v !== "boolean") throw new ToolError(`${field} must be true or false.`);
    return v;
  });
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

export const listFriends = {
  definition: {
    name: "list_friends",
    title: "List friends",
    description:
      "People who share their shifts with the user and people the user shares with, with what each side shares. " +
      "\"me\" and \"my\" in the field names are the user's side. Friends whose schedule the user hid are included with hidden: true.",
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
    title: "Get a friend's schedule",
    description:
      "A friend's shifts from `from` to `to`, both included, at most 93 days. Dates and times are the friend's " +
      "local clock in time_zone. Gross pay is included only when the friend shares their earnings with the user. " +
      "Only friends who share their shifts with the user and whom the user hasn't hidden have a schedule.",
    inputSchema: {
      type: "object",
      properties: { friend_id: friendId, from: date, to: date },
      required: ["friend_id", "from", "to"],
      additionalProperties: false,
    },
    annotations: { title: "Get a friend's schedule", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["friend_id", "from", "to"]);
    return { friend_id: requiredString(args.friend_id, "friend_id"), ...parseRange(args.from, args.to, MAX_RANGE_DAYS) };
  },
} satisfies ToolSpec;

export const listConversations = {
  definition: {
    name: "list_conversations",
    title: "List conversations",
    description:
      "The user's conversations, newest first, with the last message and the unread count of each. When has_more is true, " +
      "pass next_after_thread_id as after_thread_id for the next page.",
    inputSchema: {
      type: "object",
      properties: {
        limit: { ...limit, description: "How many conversations, 30 when left out" },
        after_thread_id: { type: "string", description: "next_after_thread_id from the previous page" },
      },
      additionalProperties: false,
    },
    annotations: { title: "List conversations", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["limit", "after_thread_id"]);
    return { limit: optionalLimit(args.limit), after_thread_id: optionalString(args.after_thread_id, "after_thread_id") };
  },
} satisfies ToolSpec;

export const readConversation = {
  definition: {
    name: "read_conversation",
    title: "Read conversation",
    description:
      "Messages in a conversation, oldest first, ending with the newest. For older ones, pass the " +
      "next_before_message_id it returns as before_message_id. Images are counted, not shown. " +
      "Reading doesn't mark the conversation read; use mark_conversation_read for that.",
    inputSchema: {
      type: "object",
      properties: {
        thread_id: threadId,
        limit: { ...limit, description: "How many messages, 30 when left out" },
        before_message_id: { type: "string", description: "Only messages older than this one" },
      },
      required: ["thread_id"],
      additionalProperties: false,
    },
    annotations: { title: "Read conversation", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["thread_id", "limit", "before_message_id"]);
    return {
      thread_id: requiredString(args.thread_id, "thread_id"),
      limit: optionalLimit(args.limit),
      before_message_id: optionalString(args.before_message_id, "before_message_id"),
    };
  },
} satisfies ToolSpec;

export const sendMessage = {
  definition: {
    name: "send_message",
    title: "Send message",
    description:
      "Sends a text message to a friend, who gets a push notification. Only text; no images. " +
      `At most ${MAX_SENDS} messages and share invitations per 10 minutes. Pass the same client_id when you ` +
      "retry a send that may have gone through, and the message is sent once.",
    inputSchema: {
      type: "object",
      properties: {
        friend_id: friendId,
        text: { type: "string", minLength: 1, maxLength: MAX_MESSAGE_LENGTH },
        client_id: { type: "string", format: "uuid", description: "A UUID you make for this message" },
      },
      required: ["friend_id", "text"],
      additionalProperties: false,
    },
    // Only a call that passes client_id is safe to repeat, so the hint stays false.
    annotations: { title: "Send message", ...reachesOthers, idempotentHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["friend_id", "text", "client_id"]);
    return {
      friend_id: requiredString(args.friend_id, "friend_id"),
      text: messageText(args.text),
      client_id: clientId(args.client_id),
    };
  },
} satisfies ToolSpec;

export const markConversationRead = {
  definition: {
    name: "mark_conversation_read",
    title: "Mark conversation read",
    description: "Marks every message in a conversation as read. The friend sees that the user has read them.",
    inputSchema: {
      type: "object",
      properties: { thread_id: threadId },
      required: ["thread_id"],
      additionalProperties: false,
    },
    annotations: { title: "Mark conversation read", readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["thread_id"]);
    return { thread_id: requiredString(args.thread_id, "thread_id") };
  },
} satisfies ToolSpec;

export const shareShiftsWith = {
  definition: {
    name: "share_shifts_with",
    title: "Share shifts with someone",
    description:
      "Starts sharing the user's shifts with another Tidex user, found by username or by a verified email address. " +
      "They get a push notification and can then see the user's schedule. Earnings stay hidden unless show_earnings is true. " +
      `Counts toward the limit of ${MAX_SENDS} messages and share invitations per 10 minutes. Confirm with the user first.`,
    inputSchema: {
      type: "object",
      properties: {
        username_or_email: { type: "string", maxLength: 254, description: "A Tidex username, with or without @, or an email address" },
        show_earnings: flag("Whether they may see the user's pay. False when left out."),
      },
      required: ["username_or_email"],
      additionalProperties: false,
    },
    annotations: { title: "Share shifts with someone", ...reachesOthers, idempotentHint: true },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["username_or_email", "show_earnings"]);
    const identifier = optionalString(args.username_or_email, "username_or_email", 254)?.trim();
    if (!identifier || identifier === "@") throw new ToolError("username_or_email is required.");
    return { identifier, show_earnings: optionalFlag(args.show_earnings, "show_earnings") ?? false };
  },
} satisfies ToolSpec;

export const updateSharing = {
  definition: {
    name: "update_sharing",
    title: "Change sharing with a friend",
    description:
      "Changes what the user shares with a friend and how the friend's shared schedule shows up. Give only what changes. " +
      "show_my_earnings and notify_them_of_my_shifts need the user to share with the friend; " +
      "hidden and notify_me_of_their_shifts need the friend to share with the user.",
    inputSchema: {
      type: "object",
      properties: {
        friend_id: friendId,
        show_my_earnings: flag("Whether the friend may see the user's pay"),
        notify_them_of_my_shifts: flag("Whether the friend gets a push when the user adds shifts"),
        hidden: flag("Whether the friend's schedule is hidden from the user's Friends tab"),
        notify_me_of_their_shifts: flag("Whether the user gets a push when the friend adds shifts"),
      },
      required: ["friend_id"],
      additionalProperties: false,
    },
    annotations: { title: "Change sharing with a friend", readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["friend_id", "show_my_earnings", "notify_them_of_my_shifts", "hidden", "notify_me_of_their_shifts"]);
    const parsed = {
      friend_id: requiredString(args.friend_id, "friend_id"),
      show_my_earnings: optionalFlag(args.show_my_earnings, "show_my_earnings"),
      notify_them_of_my_shifts: optionalFlag(args.notify_them_of_my_shifts, "notify_them_of_my_shifts"),
      hidden: optionalFlag(args.hidden, "hidden"),
      notify_me_of_their_shifts: optionalFlag(args.notify_me_of_their_shifts, "notify_me_of_their_shifts"),
    };
    const { friend_id, ...changes } = parsed;
    if (Object.values(changes).every((v) => v === undefined)) {
      throw new ToolError("Give at least one of show_my_earnings, notify_them_of_my_shifts, hidden or notify_me_of_their_shifts.");
    }
    return parsed;
  },
} satisfies ToolSpec;

export const stopSharing = {
  definition: {
    name: "stop_sharing",
    title: "Stop sharing shifts",
    description:
      "Stops sharing the user's shifts with a friend. The friend's own share with the user, if any, stays. " +
      "Sharing again needs share_shifts_with. Confirm with the user first.",
    inputSchema: {
      type: "object",
      properties: { friend_id: friendId },
      required: ["friend_id"],
      additionalProperties: false,
    },
    annotations: { title: "Stop sharing shifts", readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["friend_id"]);
    return { friend_id: requiredString(args.friend_id, "friend_id") };
  },
} satisfies ToolSpec;
