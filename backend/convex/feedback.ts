import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { requireViewer } from "./lib/auth";
import { queueFeedbackSubmitted } from "./lib/notify";
import { publicRow, reject } from "./lib/syncWrite";

/** The insert into feedback. The email comes from the account, not from the app. */
export const submit = mutation({
  args: { message: v.string() },
  handler: async (ctx, { message }) => {
    const { user } = await requireViewer(ctx);
    const length = [...message].length;
    if (length < 1 || length > 2000) reject("invalid", "feedback_message_check");
    const id = crypto.randomUUID();
    const docId = await ctx.db.insert("feedback", {
      id,
      user_id: user.id,
      message,
      user_email: user.email ?? "",
      created_at: new Date().toISOString(),
    });
    await queueFeedbackSubmitted(ctx, (await ctx.db.get(docId))!);
    return id;
  },
});

/** The viewer's own feedback and any replies, newest first. */
export const mine = query({
  args: {},
  handler: async (ctx) => {
    const { user } = await requireViewer(ctx);
    const rows = await ctx.db
      .query("feedback")
      .withIndex("by_user", (q) => q.eq("user_id", user.id))
      .collect();
    return rows.sort((a, b) => b.created_at.localeCompare(a.created_at)).map(publicRow);
  },
});
