## Generic Messaging Backend Plan

### Summary

- Build messaging as a generic `threads + messages + attachments` core now, and expose only direct friend DMs in v1.
- Gate direct-thread creation by the existing sharing graph: a DM is allowed when either user currently has an active, non-blocked `shift_shares` relationship with the other.
- Keep typing/presence out of Postgres; use Supabase Realtime broadcast on per-thread channels.
- Support image attachments in v1 with a single-image iOS composer, but make the backend multi-attachment capable so later expansion is additive.
- Do not add organization tables now. Future organizations, rooms, and feeds plug into the same `threads/messages` core without changing message storage.

### Backend Data Model

- Add `public.threads` with: `id`, `kind`, `created_by_user_id`, `title`, `avatar_url`, `metadata jsonb default '{}'`, `last_message_id`, `last_message_sender_id`, `last_message_at`, `created_at`.
- Set `threads.kind` to `text check (kind in ('direct','room','feed'))`; v1 only creates `direct`.
- Add `public.direct_threads` with: `thread_id`, `user_low_id`, `user_high_id`, `created_at`; unique on `(user_low_id, user_high_id)` to guarantee one DM per user pair.
- Add `public.thread_memberships` with: `thread_id`, `user_id`, `role`, `status`, `joined_at`, `left_at`; use `role in ('owner','admin','member','poster','reader')` and `status in ('active','left')`; v1 DMs always create two `member/active` rows.
- Add `public.thread_user_state` with: `thread_id`, `user_id`, `last_read_message_id`, `last_read_at`, `muted boolean default false`, `archived_at`, `pinned_at`, `updated_at`; primary key `(thread_id, user_id)`.
- Add `public.messages` with: `id`, `thread_id`, `sender_user_id`, `message_type`, `body`, `client_id`, `reply_to_message_id null`, `created_at`, `edited_at`, `deleted_at`, `metadata jsonb default '{}'`.
- Set `messages.message_type` to `text check (message_type in ('user','system'))`.
- Add unique idempotency constraint on `messages(thread_id, sender_user_id, client_id)`.
- Add `public.message_attachments` with: `id`, `message_id`, `attachment_index`, `kind`, `storage_bucket`, `storage_path`, `mime_type`, `byte_size`, `width`, `height`, `created_at`.
- Set `message_attachments.kind` to `text check (kind in ('image'))`; v1 only stores images but the table shape does not need to change when attachment kinds expand later.
- Add key indexes on `thread_memberships(user_id, status)`, `threads(last_message_at desc)`, `messages(thread_id, created_at desc)`, and `message_attachments(message_id, attachment_index)`.

### Authorization, RLS, and Helper Functions

- Add SQL helper `public.can_access_thread(p_thread_id uuid)` returning true when the caller has an active membership in the thread.
- Add SQL helper `public.can_post_to_thread(p_thread_id uuid)` returning true when the caller is an active member whose role is not `reader`.
- Add SQL helper `public.can_create_direct_thread(p_other_user_id uuid)` returning true when either `(owner_id = auth.uid() and viewer_id = p_other_user_id)` or `(owner_id = p_other_user_id and viewer_id = auth.uid())` exists in `shift_shares` with `blocked = false`.
- Apply RLS so `threads`, `thread_memberships`, `thread_user_state`, `messages`, and `message_attachments` are selectable only when `can_access_thread(...)` is true.
- Do not allow direct client inserts into `threads`, `direct_threads`, `thread_memberships`, `messages`, or `message_attachments`; creation goes through RPCs so idempotency, relationship checks, and attachment validation stay centralized.
- Allow direct client upsert/update on `thread_user_state` only for `user_id = auth.uid()` and only when `can_access_thread(thread_id)` is true.
- Add a private Storage bucket `message-attachments`; do not use public URLs for chat images.
- Add Storage RLS policies so authenticated users can upload only into paths of the form `{thread_id}/{auth.uid()}/{attachment_id}.{ext}` when `can_post_to_thread(thread_id)` is true.
- Add Storage RLS policies so authenticated users can download only from `message-attachments` objects whose first path segment is a thread they can access.

### RPCs and Public Interfaces

- Add `public.get_or_create_direct_thread(p_other_user_id uuid)`; it verifies `can_create_direct_thread`, normalizes the user pair, creates `threads/direct_threads/thread_memberships/thread_user_state` atomically if missing, and returns the canonical thread summary plus counterpart profile fields needed by the client.
- Add `public.list_my_threads(p_limit integer default 30, p_before timestamptz default null)`; it returns thread summary, unread count, counterpart profile data for `direct` threads, and latest message preview.
- Add `public.list_thread_messages(p_thread_id uuid, p_limit integer default 50, p_before_created_at timestamptz default null)`; it returns canonical message rows with ordered attachment metadata.
- Add `public.send_message(p_thread_id uuid, p_client_id uuid, p_body text, p_attachments jsonb default '[]')`; it validates posting rights, enforces `0..4` attachments, verifies each attachment path belongs to the caller and thread and exists in Storage metadata, inserts the message plus attachment rows in one transaction, updates `threads.last_message_*`, and returns the canonical inserted payload.
- Add `public.mark_thread_read(p_thread_id uuid, p_through_message_id uuid)`; it upserts `thread_user_state` and clears unread count for that caller up to the supplied message.
- Add `public.set_thread_muted(p_thread_id uuid, p_muted boolean)` and `public.archive_thread(p_thread_id uuid, p_archived boolean)` as thin helpers over `thread_user_state`.
- Return counterpart profile data from the listing RPCs using the same pattern already used by sharing: read `auth.users` metadata and `user_settings.profile_picture_url` inside `SECURITY DEFINER` functions.

### Realtime, Presence, and Notifications

- Enable Realtime publication for `threads`, `messages`, and `thread_user_state`.
- Subscribe detail views to `postgres_changes` on `messages` filtered by `thread_id`; on insert/update events, the client fetches the canonical payload by message id or reloads the latest page so attachments and derived fields stay consistent.
- Subscribe list views to `threads` and `thread_user_state` so last-message preview and unread state update without polling.
- Use Realtime broadcast on channel `thread:{thread_id}` for `typing_start` and `typing_stop`.
- Auto-clear typing indicators client-side after 5 seconds without a refresh event; do not persist typing state in SQL.
- Add trigger `public.queue_thread_message_notification()` on `messages after insert`; it enqueues one outbox row per active thread member except the sender.
- Skip push enqueue when the recipient has `thread_user_state.muted = true`.
- Set notification payload type to `thread_message` with `thread_id`, `message_id`, and `thread_kind`.
- Build notification copy as: use trimmed body preview when present; otherwise use `"{sender} sent an image"` for image-only messages.
- Use idempotency key `thread_message:{message_id}:{recipient_id}` in `internal.notifications_outbox`.
- Do not suppress push notifications based on live presence in v1; that can be added later without schema changes.

### Image Attachment Pipeline

- Reuse the existing direct-upload pattern rather than base64-posting images through the app server.
- iOS compresses off-main before upload; target max long edge `2048px`, preferred format `webp`, fallback `heic`, then `jpeg`.
- Accept `image/webp`, `image/heic`, `image/heif`, `image/jpeg`, and `image/png`.
- Set v1 hard limits to `1` image in the iOS composer, `4` attachments max in the backend RPC, and `5 MB` max per uploaded object after compression.
- Upload the image first to Storage path `{thread_id}/{user_id}/{attachment_id}.{ext}` using the authenticated Supabase client.
- Call `send_message` only after upload succeeds; pass attachment descriptors with `attachment_id`, `storage_path`, `mime_type`, `byte_size`, `width`, and `height`.
- On send failure after upload, keep the local pending message and retry with the same `client_id` and `attachment_id`; the RPC idempotency constraint prevents duplicate persisted messages.
- Add a cleanup job for orphaned uploads later than 24 hours old that are still not referenced by `message_attachments`; implement it as a small service-role cleanup path, but it is non-blocking for v1 launch.

### iOS Architecture Changes

- Do not reuse the Wagey `LocalConversation`; create dedicated SwiftData models for `LocalThread`, `LocalThreadState`, `LocalMessage`, and `LocalMessageAttachment`.
- Add a dedicated `MessagingRepository`; do not route chat through `SyncCoordinator` because the chat path needs optimistic writes and live subscriptions, not batch sync semantics.
- The repository owns: thread list loading, detail pagination, Realtime subscriptions, optimistic local sends, image upload, retry, read-state updates, and mute/archive actions.
- Use optimistic local statuses on messages: `uploading`, `sending`, `sent`, `failed`.
- Store the single selected image in the composer UI, but store attachments as an array in local models and server DTOs so multiple-image UI is a future UI-only change.
- Reuse the current image-processing approach from profile uploads and the current one-image composer interaction from Wagey rather than inventing a new image pipeline.
- Cache downloaded chat images locally by storage path; do not treat message attachments as public URL assets.

### Web / Future-Scope Compatibility

- No organization or group product is exposed in v1, but the schema stays stable because `threads/messages/message_attachments` are already generic.
- Future group chat adds more `thread_memberships` rows and starts creating `threads.kind = 'room'`; no storage or message-table redesign is needed.
- Future organization feeds add an org-scoped linkage table and access helper, then start creating `threads.kind = 'feed'`; existing `messages`, `attachments`, `thread_user_state`, Realtime, and push logic remain unchanged.
- The only future additions expected for organizations are new access tables/helpers and possibly extra membership derivation logic; existing DM tables do not need to be renamed or migrated.

### Test Plan

- SQL/RLS tests for `get_or_create_direct_thread`: allowed with either active share direction, denied when no share exists, denied when the only share is blocked.
- SQL/RLS tests for reads: non-members cannot select `threads`, `messages`, `message_attachments`, or Storage objects.
- SQL tests for `send_message`: text-only, image-only, text-plus-image, invalid storage path, wrong sender prefix, too many attachments, duplicate `client_id`, and retry semantics.
- Storage-policy tests: valid upload path allowed, wrong thread path denied, wrong sender path denied, non-member download denied.
- Trigger tests for `queue_thread_message_notification`: sender excluded, muted recipient skipped, image-only body copy correct, idempotency key correct.
- Realtime acceptance tests: new message appears in detail view without reload; thread list preview/unread count updates; typing indicator appears/disappears without DB writes.
- iOS acceptance tests: optimistic send appears immediately, failed upload/send is retryable, mark-read updates unread badge, image-only message renders correctly, and reopening a thread hydrates from SwiftData before network refresh.

### Assumptions and Defaults

- Direct messages are permitted on any active, non-blocked share relationship; mutual sharing is not required.
- V1 exposes direct threads only; `room` and `feed` kinds are reserved for later.
- V1 iOS composer supports one image, but backend and local models support multiple attachments without schema changes.
- Chat attachments are private assets; no public bucket and no public URL strategy will be used.
- Push notifications are always sent for new messages unless the recipient muted the thread; live-presence-based suppression is intentionally deferred.
- No organization schema is added now; future organization support is achieved by attaching new access rules to the existing thread core rather than changing message storage.
