import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { getViewer } from "./lib/auth";
import { reject } from "./lib/syncWrite";
import { literals } from "./lib/validators";

const PER_INSTALL_PER_HOUR = 120;
const ANONYMOUS_PER_HOUR = 3000;

const text = (value: string | undefined, max: number) => value?.slice(0, max) || undefined;

/**
 * Port of record_auth_diagnostic_event. Signed-out calls are accepted, because the app
 * reports launch and session failures after it has lost its session. Those need an
 * install_id in metadata and are capped per install and overall, and a claimed user id
 * stays in metadata instead of user_id.
 */
export const recordAuthEvent = mutation({
  args: {
    event_type: literals(
      "app_launch",
      "initial_session_received",
      "initial_session_missing",
      "initial_session_check_failed",
      "initial_session_timeout",
      "auth_state_changed",
      "authenticated",
      "signed_out_received",
      "user_initiated_sign_out",
      "session_fetch_failed",
      "token_refresh_started",
      "token_refresh_succeeded",
      "token_refresh_failed",
      "foreground_session_failed",
      "revoked_session_detected",
      "recoverable_auth_failure",
      "forced_unauthenticated",
    ),
    severity: v.optional(literals("debug", "info", "warning", "error")),
    user_id: v.optional(v.string()),
    app_state: v.optional(v.string()),
    auth_event: v.optional(v.string()),
    app_version: v.optional(v.string()),
    build_number: v.optional(v.string()),
    os_version: v.optional(v.string()),
    device_model: v.optional(v.string()),
    locale: v.optional(v.string()),
    error_kind: v.optional(v.string()),
    error_message: v.optional(v.string()),
    metadata: v.optional(v.record(v.string(), v.any())),
  },
  handler: async (ctx, args) => {
    let metadata: Record<string, unknown> = args.metadata ?? {};
    if (JSON.stringify(metadata).length > 4096) reject("invalid", "Diagnostic metadata is too large");
    const viewer = await getViewer(ctx);
    const now = new Date();
    let userId: string | undefined;
    if (viewer !== null) {
      if (args.user_id !== undefined && args.user_id !== viewer.user.id) {
        reject("invalid", "Diagnostic user id does not match authenticated user");
      }
      userId = viewer.user.id;
    } else {
      const installId = typeof metadata.install_id === "string" ? metadata.install_id.slice(0, 80) : "";
      if (installId === "") reject("invalid", "Anonymous diagnostics require an install id");
      const hourAgo = new Date(now.getTime() - 3_600_000).toISOString();
      const anonymous = await ctx.db
        .query("auth_diagnostic_events")
        .withIndex("by_user_occurred_at", (q) => q.eq("user_id", undefined).gte("occurred_at", hourAgo))
        .take(ANONYMOUS_PER_HOUR);
      if (
        anonymous.length >= ANONYMOUS_PER_HOUR ||
        anonymous.filter((e) => e.metadata?.install_id === installId).length >= PER_INSTALL_PER_HOUR
      ) {
        reject("rate_limited", "Diagnostic rate limit exceeded");
      }
      if (args.user_id !== undefined) metadata = { ...metadata, reported_user_id: args.user_id };
    }
    const iso = now.toISOString();
    await ctx.db.insert("auth_diagnostic_events", {
      id: crypto.randomUUID(),
      user_id: userId,
      occurred_at: iso,
      event_type: args.event_type,
      severity: args.severity ?? "info",
      app_state: text(args.app_state, 80),
      auth_event: text(args.auth_event, 80),
      app_version: text(args.app_version, 40),
      build_number: text(args.build_number, 40),
      os_version: text(args.os_version, 80),
      device_model: text(args.device_model, 80),
      locale: text(args.locale, 40),
      error_kind: text(args.error_kind, 120),
      error_message: text(args.error_message, 500),
      metadata,
      created_at: iso,
    });
    return { success: true };
  },
});
