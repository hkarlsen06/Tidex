import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { literals } from "./lib/validators";

// Conventions:
// - Tables and fields match the Postgres tables and columns, so the migration copies rows
//   as they are and the app's Codable models keep decoding them.
// - uuid columns are lowercase strings. Rows point to each other by uuid, and user_id
//   style fields hold `users.id`. Convex does not enforce foreign keys, so account
//   deletion has to clean up every table that holds a user's uuid.
// - Timestamps are ISO-8601 UTC strings in `Date.toISOString()` form, so they sort as
//   strings. The migration converts Postgres timestamps to that form. Dates are YYYY-MM-DD.
// - Nullable columns are v.optional(...) and are omitted when null.
// - jsonb columns are v.any() until the functions that write them are ported.
// - `revision` comes from lib/revision.ts. It increases across all tables, so
//   `revision > cursor` on a `by_*_revision` index is the sync cursor. A write that
//   changes a row gives it a new revision.
// - Partial SQL indexes are full indexes here. Callers filter the rest in code.
const uuid = v.string();
const ts = v.string();
const date = v.string();
const json = v.any();
const optUuid = v.optional(uuid);
const optTs = v.optional(ts);
const optDate = v.optional(date);
const optString = v.optional(v.string());
const optNumber = v.optional(v.number());
const optJson = v.optional(json);
const halfTaxMonth = v.optional(v.union(v.literal(11), v.literal(12)));

export default defineSchema({
  // One document. Holds the last revision handed out. See lib/revision.ts.
  revision_counter: defineTable({ value: v.number() }),

  // Replaces auth.users. Convex finds the row from the Clerk token by clerk_user_id.
  // `id` is the uuid every other table uses. Users from Postgres keep their Supabase
  // uuid in both `id` and `supabase_user_id`. Users who sign up on N+1 get a new uuid
  // and no supabase_user_id.
  users: defineTable({
    id: uuid,
    supabase_user_id: optUuid,
    // Missing for GoTrue users who signed in only by phone. N+1 has no SMS sign-in, so
    // they get no Clerk user. An admin can link one by hand if they get in touch.
    clerk_user_id: optString,
    email: optString,
    // From the sign-in provider (raw_user_meta_data name/full_name and avatar_url/picture).
    name: optString,
    avatar_url: optString,
    locale: optString,
    // raw_app_meta_data.role in GoTrue.
    role: v.optional(v.literal("admin")),
    // Sign-in methods, such as "apple", "google" and "email". GoTrue's
    // raw_app_meta_data.providers for migrated users, Clerk's accounts for new ones.
    providers: v.optional(v.array(v.string())),
    banned_at: optTs,
    last_sign_in_at: optTs,
    created_at: ts,
    revision: v.number(),
  })
    .index("by_uuid", ["id"])
    .index("by_clerk_user_id", ["clerk_user_id"])
    .index("by_supabase_user_id", ["supabase_user_id"])
    .index("by_email", ["email"])
    .index("by_role", ["role"])
    .index("by_revision", ["revision"]),

  // Apple and Google account ids (`sub`) from auth.identities, copied by the migration.
  // users.linkOrCreate matches on them when Clerk could not link a sign-in by email.
  legacy_identities: defineTable({
    provider: literals("apple", "google"),
    sub: v.string(),
    user_id: uuid,
  }).index("by_provider_sub", ["provider", "sub"]),

  // More Clerk users for one users row. Created when users.linkOrCreate matches a new
  // Clerk user to an imported one by legacy sub. Deleting or banning an account must
  // act on these Clerk users too.
  clerk_user_aliases: defineTable({
    clerk_user_id: v.string(),
    user_id: uuid,
    created_at: ts,
  })
    .index("by_clerk_user_id", ["clerk_user_id"])
    .index("by_user", ["user_id"]),

  // `id` is the user's uuid.
  profiles: defineTable({
    id: uuid,
    before_paywall: v.boolean(),
    username: optString,
    last_synced_at: optTs,
    created_at: ts,
    updated_at: ts,
    revision: v.number(),
  })
    .index("by_uuid", ["id"])
    .index("by_username", ["username"])
    .index("by_revision", ["revision"]),

  // ---- Tables the sync coordinator pulls ----

  jobs: defineTable({
    id: uuid,
    user_id: uuid,
    name: v.string(),
    color: optString,
    is_default: v.boolean(),
    sort_order: v.number(),
    payroll_day: optNumber,
    half_tax_month: halfTaxMonth,
    monthly_goal: optNumber,
    archived_at: optTs,
    deleted_at: optTs,
    created_at: ts,
    updated_at: ts,
    revision: v.number(),
    currency: v.string(),
    pay_period: optJson,
  })
    .index("by_uuid", ["id"])
    .index("by_user_revision", ["user_id", "revision"]),

  user_shifts: defineTable({
    id: uuid,
    user_id: uuid,
    job_id: uuid,
    shift_date: date,
    start_time: v.string(),
    end_time: v.string(),
    custom_supplements: optJson,
    custom_pause_windows: optJson,
    note: optString,
    deleted_at: optTs,
    created_at: optTs,
    updated_at: ts,
    revision: v.number(),
  })
    .index("by_uuid", ["id"])
    .index("by_user_revision", ["user_id", "revision"])
    .index("by_user_shift_date", ["user_id", "shift_date"])
    .index("by_job", ["job_id"]),

  events: defineTable({
    id: uuid,
    user_id: uuid,
    start_date: date,
    end_date: date,
    is_all_day: v.boolean(),
    start_time: optString,
    end_time: optString,
    note: v.string(),
    notification_minutes_array: v.optional(v.array(v.number())),
    notification_anchor_time: optString,
    deleted_at: optTs,
    created_at: ts,
    updated_at: ts,
    revision: v.number(),
  })
    .index("by_uuid", ["id"])
    .index("by_user_revision", ["user_id", "revision"])
    .index("by_user_start_date", ["user_id", "start_date"]),

  recurring_shifts: defineTable({
    id: uuid,
    user_id: uuid,
    job_id: uuid,
    // `time with time zone` in Postgres, for example "08:00:00+00".
    start_time: v.string(),
    end_time: v.string(),
    repeat_interval_weeks: v.number(),
    selected_days: json,
    end_condition: optJson,
    exclusions: optJson,
    date_specific_supplements: optJson,
    date_specific_pause_windows: optJson,
    date_specific_notes: optJson,
    deleted_at: optTs,
    created_at: ts,
    updated_at: ts,
    revision: v.number(),
  })
    .index("by_uuid", ["id"])
    .index("by_user_revision", ["user_id", "revision"])
    .index("by_job", ["job_id"]),

  wage_snapshots: defineTable({
    id: uuid,
    user_id: uuid,
    job_id: uuid,
    // Missing for the job's base snapshot. At most one live row per (user, job, from_date).
    from_date: optDate,
    hourly_wage: v.number(),
    wage_level: optNumber,
    supplements: json,
    tax_enabled: v.optional(v.boolean()),
    tax_percentage: optNumber,
    break_enabled: v.optional(v.boolean()),
    break_method: v.optional(literals("proportional", "base_only", "end_of_shift", "none")),
    break_threshold_hours: optNumber,
    break_deduction_minutes: optNumber,
    tariff_type_id: optString,
    overtime: json,
    deleted_at: optTs,
    created_at: optTs,
    updated_at: ts,
    revision: v.number(),
  })
    .index("by_uuid", ["id"])
    .index("by_user_revision", ["user_id", "revision"])
    .index("by_user_job_from_date", ["user_id", "job_id", "from_date"])
    .index("by_job", ["job_id"]),

  payroll_adjustments: defineTable({
    id: uuid,
    user_id: uuid,
    job_id: optUuid,
    amount: v.number(),
    currency: v.string(),
    category: literals("retro_pay", "bonus", "correction", "other"),
    tax_treatment: literals("gross_taxable", "net_manual", "excluded_from_tax_estimate"),
    description: v.string(),
    note: optString,
    earned_from_date: optDate,
    earned_to_date: optDate,
    payout_date: date,
    curated_note: optString,
    curated_link: optString,
    curated_description: optString,
    curated_link_title: optString,
    deleted_at: optTs,
    created_at: ts,
    updated_at: ts,
    revision: v.number(),
  })
    .index("by_uuid", ["id"])
    .index("by_user_revision", ["user_id", "revision"])
    .index("by_job", ["job_id"]),

  // One row per user.
  user_settings: defineTable({
    user_id: uuid,
    monthly_goal: optNumber,
    monthly_goals_by_month: json,
    default_shifts_view: v.optional(literals("list", "calendar")),
    // Replaces profile_picture_url. Queries return the file URL.
    profile_picture_storage_id: v.optional(v.id("_storage")),
    payroll_day: optNumber,
    half_tax_month: halfTaxMonth,
    currency: optString,
    theme: literals("light", "dark", "system"),
    calendar_animation_style: literals("horizontal", "vertical"),
    calendar_content_color_style: literals("workplace", "monochrome"),
    default_startup_tab: literals("home", "shifts", "add", "stats", "sharing"),
    show_dashboard_clock_buttons: v.boolean(),
    ai_data_sharing_enabled: v.boolean(),
    wagey_showcase_seen: v.boolean(),
    last_active: optTs,
    created_at: optTs,
    updated_at: ts,
    revision: v.number(),
  }).index("by_user_revision", ["user_id", "revision"]),

  // One row per user. Postgres has no revision column here. The app pulls it by updated_at.
  notification_preferences: defineTable({
    user_id: uuid,
    shared_shifts_enabled: v.boolean(),
    shift_reminders_enabled: v.boolean(),
    shift_reminder_minutes_array: v.optional(v.array(v.number())),
    updated_at: ts,
    revision: v.number(),
  }).index("by_user_revision", ["user_id", "revision"]),

  // ---- Sharing ----

  shift_shares: defineTable({
    id: uuid,
    owner_id: uuid,
    viewer_id: uuid,
    show_earnings: v.boolean(),
    blocked: v.boolean(),
    blocked_by_user_id: optUuid,
    muted: v.boolean(),
    owner_muted: v.boolean(),
    hidden: v.boolean(),
    created_at: ts,
    revision: v.number(),
  })
    .index("by_uuid", ["id"])
    .index("by_owner_viewer", ["owner_id", "viewer_id"])
    .index("by_owner_revision", ["owner_id", "revision"])
    .index("by_viewer_revision", ["viewer_id", "revision"]),

  // ---- Messaging ----
  // thread_events, inbox_events, user_inbox_sync_state and threads.state_version are
  // not here. They fed Realtime and the versioned sync RPCs. The app subscribes to
  // threads.inbox and messages.thread instead, and catches up on older messages with
  // messages.changes, which pages by_thread_revision.

  threads: defineTable({
    id: uuid,
    kind: literals("direct", "room", "feed"),
    created_by_user_id: optUuid,
    title: optString,
    // Replaces avatar_url. Queries return the file URL.
    avatar_storage_id: v.optional(v.id("_storage")),
    metadata: json,
    last_message_id: optUuid,
    last_message_sender_id: optUuid,
    last_message_at: ts,
    created_at: ts,
    revision: v.number(),
  }).index("by_uuid", ["id"]),

  // Finds the direct thread for a pair of users. user_low_id < user_high_id.
  direct_threads: defineTable({
    thread_id: uuid,
    user_low_id: uuid,
    user_high_id: uuid,
    created_at: ts,
  })
    .index("by_thread", ["thread_id"])
    .index("by_pair", ["user_low_id", "user_high_id"])
    .index("by_user_high", ["user_high_id"]),

  thread_memberships: defineTable({
    thread_id: uuid,
    user_id: uuid,
    role: literals("owner", "admin", "member", "poster", "reader"),
    status: literals("active", "left"),
    joined_at: ts,
    left_at: optTs,
    revision: v.number(),
  })
    .index("by_thread_user", ["thread_id", "user_id"])
    .index("by_user_revision", ["user_id", "revision"]),

  thread_user_state: defineTable({
    thread_id: uuid,
    user_id: uuid,
    last_read_message_id: optUuid,
    last_read_at: optTs,
    muted: v.boolean(),
    archived_at: optTs,
    unread_count: v.number(),
    updated_at: ts,
    revision: v.number(),
  })
    .index("by_thread_user", ["thread_id", "user_id"])
    .index("by_user_revision", ["user_id", "revision"]),

  messages: defineTable({
    id: uuid,
    thread_id: uuid,
    sender_user_id: uuid,
    message_type: literals("user", "system"),
    body: optString,
    // Set by the sending device. Resending the same client_id returns the existing row.
    client_id: uuid,
    reply_to_message_id: optUuid,
    metadata: json,
    created_at: ts,
    edited_at: optTs,
    deleted_at: optTs,
    revision: v.number(),
  })
    .index("by_uuid", ["id"])
    .index("by_thread_revision", ["thread_id", "revision"])
    .index("by_thread_created_at", ["thread_id", "created_at", "id"])
    .index("by_thread_sender_client", ["thread_id", "sender_user_id", "client_id"])
    .index("by_sender", ["sender_user_id"]),

  // Rows never change after insert, so the app gets them with their message and they
  // have no revision.
  message_attachments: defineTable({
    id: uuid,
    message_id: uuid,
    attachment_index: v.number(),
    kind: v.literal("image"),
    // Replaces storage_bucket and storage_path.
    storage_id: v.id("_storage"),
    mime_type: v.string(),
    byte_size: v.number(),
    width: optNumber,
    height: optNumber,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_message", ["message_id", "attachment_index"]),

  // Reactions reach the app inside their message's payload. A toggle gives the message a
  // new revision, so removing a reaction can delete the row and still sync.
  message_reactions: defineTable({
    id: uuid,
    thread_id: uuid,
    message_id: uuid,
    // Set when the reaction is on one image of the message.
    attachment_id: optUuid,
    user_id: uuid,
    emoji: v.string(),
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_message_user_emoji", ["message_id", "user_id", "emoji"])
    .index("by_attachment", ["attachment_id"])
    .index("by_user", ["user_id"]),

  // Images uploaded through POST /attachments on the HTTP actions domain and not sent
  // yet. messages.send accepts only the caller's own upload for that thread, as the
  // Postgres check on storage.objects.owner_id did, and deletes the row.
  attachment_uploads: defineTable({
    storage_id: v.id("_storage"),
    user_id: uuid,
    thread_id: uuid,
    created_at: ts,
  })
    .index("by_storage_id", ["storage_id"])
    .index("by_created_at", ["created_at"]),

  // Who is typing in which thread. Replaces the Realtime typing broadcasts. Rows older
  // than a few seconds are stale, and the app ignores them by updated_at.
  typing_indicators: defineTable({
    thread_id: uuid,
    user_id: uuid,
    updated_at: ts,
  })
    .index("by_thread_user", ["thread_id", "user_id"])
    .index("by_updated_at", ["updated_at"]),

  abuse_reports: defineTable({
    id: uuid,
    reporter_user_id: uuid,
    reported_user_id: uuid,
    thread_id: uuid,
    message_id: optUuid,
    reason: literals(
      "harassment_or_bullying",
      "sexual_content",
      "hate_or_discriminatory_content",
      "violence_or_threats",
      "spam",
      "inappropriate_profile_or_conduct",
      "other",
    ),
    note: optString,
    status: literals("open", "in_review", "actioned", "dismissed"),
    reviewer_notes: optString,
    reviewed_at: optTs,
    reviewed_by: optUuid,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_status_created_at", ["status", "created_at"])
    .index("by_reporter", ["reporter_user_id"])
    .index("by_reported_user", ["reported_user_id", "created_at"]),

  // ---- Account ----

  // One row per user. Stripe fields stay for the old rows.
  subscriptions: defineTable({
    id: uuid,
    user_id: uuid,
    provider: literals("stripe", "apple", "admin_trial"),
    provider_subscription_id: optString,
    status: literals(
      "active",
      "trialing",
      "past_due",
      "incomplete",
      "paused",
      "canceled",
      "incomplete_expired",
      "unpaid",
      "grace",
      "expired",
      "refunded",
    ),
    product_id: optString,
    price_id: optString,
    price_display: optString,
    current_period_start: optTs,
    current_period_end: optTs,
    cancel_at_period_end: v.optional(v.boolean()),
    cancel_at: optTs,
    canceled_at: optTs,
    cancellation_reason: optString,
    cancellation_feedback: optString,
    cancellation_comment: optString,
    stripe_customer_id: optString,
    stripe_subscription_id: optString,
    apple_original_transaction_id: optString,
    apple_last_transaction_id: optString,
    apple_environment: v.optional(literals("Production", "Sandbox")),
    app_account_token: optUuid,
    raw_provider_payload: optJson,
    created_at: optTs,
    updated_at: ts,
    revision: v.number(),
  })
    .index("by_uuid", ["id"])
    .index("by_user", ["user_id"])
    .index("by_apple_original_transaction_id", ["apple_original_transaction_id"])
    .index("by_provider_subscription_id", ["provider", "provider_subscription_id"])
    .index("by_current_period_end", ["current_period_end"]),

  feedback: defineTable({
    id: uuid,
    user_id: uuid,
    message: v.string(),
    user_email: v.string(),
    response: optString,
    responded_at: optTs,
    responded_by: optUuid,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_user", ["user_id"])
    .index("by_created_at", ["created_at"]),

  onboarding_funnel_steps: defineTable({
    user_id: uuid,
    step: v.string(),
    reached_at: ts,
    recorded_at: ts,
  }).index("by_user_step", ["user_id", "step"]),

  // ---- Server-only tables (internal schema in Postgres) ----

  admin_audit_log: defineTable({
    id: uuid,
    admin_id: optUuid,
    admin_email: v.string(),
    action: v.string(),
    target_user_id: optUuid,
    target_email: optString,
    metadata: optJson,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_created_at", ["created_at"])
    .index("by_target_user", ["target_user_id", "created_at"]),

  admin_broadcasts: defineTable({
    id: uuid,
    admin_id: uuid,
    title: optString,
    body: optString,
    deeplink: optString,
    title_no: optString,
    body_no: optString,
    deeplink_no: optString,
    target: literals("all", "pro", "active", "new", "specific"),
    target_count: v.number(),
    status: literals("pending", "queued", "partial_failure", "complete"),
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_created_at", ["created_at"]),

  // The appAccountToken the app passes to StoreKit. Apple notifications carry it.
  app_account_tokens: defineTable({
    user_id: uuid,
    token: uuid,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_user", ["user_id"])
    .index("by_token", ["token"]),

  // One row per user per hour the app was open. Purged after 32 days.
  app_activity_hours: defineTable({
    hour: ts,
    user_id: uuid,
  })
    .index("by_hour_user", ["hour", "user_id"])
    .index("by_user", ["user_id"]),

  user_app_activity: defineTable({
    user_id: uuid,
    first_active_at: ts,
    last_active_at: ts,
    open_count: v.number(),
    active_days: v.number(),
    app_version: optString,
    build_number: optString,
    previous_app_version: optString,
    previous_build_number: optString,
    os_version: optString,
    device_model: optString,
    locale: optString,
    time_zone: optString,
    app_language: optString,
    notification_permission: optString,
    background_refresh: optString,
    widget_kinds: v.optional(v.array(v.string())),
    appearance: optString,
    text_size: optString,
    reduce_motion: v.optional(v.boolean()),
  })
    .index("by_user", ["user_id"])
    .index("by_last_active_at", ["last_active_at"]),

  // `id` is Apple's notificationUUID.
  apple_notifications: defineTable({
    id: v.string(),
    notification_type: v.string(),
    subtype: optString,
    original_transaction_id: optString,
    transaction_id: optString,
    received_at: ts,
    processed_at: optTs,
    attempts: v.number(),
    last_error: optString,
    raw_payload: optJson,
  }).index("by_uuid", ["id"]),

  // Apple notifications that matched no user yet.
  apple_orphan_notifications: defineTable({
    id: v.string(),
    notification_type: v.string(),
    subtype: optString,
    original_transaction_id: optString,
    app_account_token: optUuid,
    received_at: ts,
    raw_payload: json,
    reconciled_at: optTs,
    reconciled_user_id: optUuid,
  })
    .index("by_uuid", ["id"])
    .index("by_original_transaction_id", ["original_transaction_id"])
    .index("by_app_account_token", ["app_account_token"]),

  auth_diagnostic_events: defineTable({
    id: uuid,
    user_id: optUuid,
    occurred_at: ts,
    event_type: v.string(),
    severity: literals("debug", "info", "warning", "error"),
    app_state: optString,
    auth_event: optString,
    app_version: optString,
    build_number: optString,
    os_version: optString,
    device_model: optString,
    locale: optString,
    error_kind: optString,
    error_message: optString,
    metadata: json,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_occurred_at", ["occurred_at"])
    .index("by_user_occurred_at", ["user_id", "occurred_at"]),

  // Only the hash of the feed token is stored. At most one unrevoked row per user.
  calendar_subscription_tokens: defineTable({
    id: uuid,
    user_id: uuid,
    token_hash: v.string(),
    token_suffix: v.string(),
    content_mode: literals("events_only", "shifts_only", "shifts_and_events"),
    revoked_at: optTs,
    last_used_at: optTs,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_token_hash", ["token_hash"])
    .index("by_user", ["user_id"]),

  // Impersonation happens in Convex, not in Clerk. The admin stays signed in as
  // themselves, and while their session is active and not expired, the current-user
  // lookup returns target_user_id instead. The table starts empty at cutover, and the
  // audit log keeps the history. impersonation_rate_limits is not ported. Rate limits
  // count this admin's recent sessions instead.
  impersonation_sessions: defineTable({
    id: uuid,
    admin_user_id: uuid,
    target_user_id: uuid,
    reason: v.string(),
    created_at: ts,
    expires_at: ts,
    ended_at: optTs,
    ended_by_admin_user_id: optUuid,
  })
    .index("by_uuid", ["id"])
    .index("by_admin_ended_at", ["admin_user_id", "ended_at"])
    .index("by_admin_created_at", ["admin_user_id", "created_at"]),

  impersonation_audit_log: defineTable({
    id: uuid,
    session_id: optUuid,
    admin_user_id: optUuid,
    target_user_id: optUuid,
    action: literals("start", "stop", "action_blocked", "session_expired"),
    reason: optString,
    admin_ip: optString,
    admin_user_agent: optString,
    metadata: optJson,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_created_at", ["created_at"]),

  push_devices: defineTable({
    id: uuid,
    user_id: uuid,
    // Unique per device.
    fcm_token: v.string(),
    platform: literals("ios", "android", "web"),
    device_id: optString,
    device_model: optString,
    app_version: optString,
    apns_token: optString,
    apns_environment: v.optional(literals("production", "sandbox")),
    live_activity_push_to_start_token: optString,
    time_zone: v.string(),
    last_seen_at: ts,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_user", ["user_id"])
    .index("by_fcm_token", ["fcm_token"])
    .index("by_apns_token", ["apns_token"])
    .index("by_live_activity_push_to_start_token", ["live_activity_push_to_start_token"]),

  live_activity_deliveries: defineTable({
    id: uuid,
    push_device_id: uuid,
    shift_id: v.string(),
    status: literals("starting", "active", "ending", "ended", "failed"),
    activity_id: optString,
    update_token: optString,
    claimed_at: optTs,
    start_sent_at: optTs,
    active_at: optTs,
    end_sent_at: optTs,
    ended_at: optTs,
    attempts: v.number(),
    last_error: optString,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_push_device_shift", ["push_device_id", "shift_id"])
    .index("by_status_updated_at", ["status", "updated_at"])
    .index("by_activity_id", ["activity_id"])
    .index("by_update_token", ["update_token"]),

  // Push notifications waiting to be sent, and the ones sent recently.
  notifications_outbox: defineTable({
    id: uuid,
    owner_id: optUuid,
    recipient_id: uuid,
    broadcast_id: optUuid,
    thread_id: optUuid,
    notification_type: v.string(),
    title: v.string(),
    body: v.string(),
    data_payload: json,
    idempotency_key: v.string(),
    status: literals("pending", "sending", "sent", "failed", "skipped"),
    due_at: ts,
    claimed_at: optTs,
    processed_at: optTs,
    attempts: v.number(),
    error_message: optString,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_status_due_at", ["status", "due_at"])
    .index("by_idempotency_key", ["idempotency_key"])
    .index("by_recipient_type_thread", ["recipient_id", "notification_type", "thread_id"])
    .index("by_owner_type_status", ["owner_id", "notification_type", "status"])
    .index("by_broadcast", ["broadcast_id"]),

  // Onboarding steps reached before sign-in, keyed by a random install id.
  onboarding_preauth_steps: defineTable({
    install_id: uuid,
    step: v.string(),
    reached_at: ts,
    recorded_at: ts,
  })
    .index("by_install_step", ["install_id", "step"])
    .index("by_recorded_at", ["recorded_at"]),

  // One document.
  paywall_config: defineTable({
    free_trial_enabled: v.boolean(),
    free_trial_duration_days: v.number(),
    free_trial_reminder_days_before_end: v.number(),
    created_at: ts,
    updated_at: ts,
  }),

  // `id` is a slug such as "hk_retail".
  tariff_types: defineTable({
    id: v.string(),
    display_name: v.string(),
    description: optString,
    country: v.string(),
    is_default: v.optional(v.boolean()),
    created_at: optTs,
  }).index("by_uuid", ["id"]),

  tariff_versions: defineTable({
    id: uuid,
    tariff_type_id: v.string(),
    effective_date: date,
    name: optString,
    rates: json,
    supplements: json,
    overtime: json,
    created_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_type_effective_date", ["tariff_type_id", "effective_date"]),
});
