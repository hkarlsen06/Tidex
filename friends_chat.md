## Friends Messaging Plan

### Spec Conventions

- Unless a bullet is explicitly marked `Should` or `Later`, treat it as `Must` for the first App Store-ready v1.
- `Must` means launch-blocking for implementation, QA, and App Review.
- `Should` means desirable for v1 if low-risk, but it can slip without changing the core product promise.
- `Later` means intentionally out of scope for the first iOS release and should not delay launch.

### Launch Summary

- `Must`: direct 1:1 messaging inside the existing iOS Friends tab, friend-list chat entry points, thread detail, text plus single-image sending, private attachments, report/block/support/legal surfaces, moderation, feature flagging, and test coverage for auth/send/read/realtime/report/block flows.
- `Should`: lightweight UI polish such as temporary return highlights, richer large-device header presentation, and other non-essential visual refinements that do not change behavior.
- `Later`: inbox UI, group chat, org chat, replies, reactions, edit/delete, in-thread search, archive management, camera/audio/video/file attachments, and web messaging UI.

### Locked Product Decisions

- Ship messaging as a generic `threads + messages + attachments` backend, but expose only 1:1 friend messaging in v1.
- Put messaging inside the existing iOS Friends tab. Do not add a new top-level app tab for chat.
- Keep the current Friends tab structure centered on the main friend list. Do not add an inbox screen or segmented control in v1.
- Add a dedicated chat action to each friend card in the main Friends list. That action is the primary entry point into chat.
- Gate new direct-thread creation by the existing sharing graph: a user can start a DM when either direction of `shift_shares` is active and not blocked.
- Existing direct threads remain accessible even if the underlying share relationship later changes. v1 gates creation, not continued access.
- Keep typing and live presence out of Postgres. Use Supabase Realtime broadcast on per-thread channels.
- Support image attachments in v1 with a single-image iOS composer, but keep the backend multi-attachment capable so later expansion is additive.
- Reuse Wagey's chat UI patterns through a shared chat UI layer. Do not build a second standalone chat surface just for Friends.

### iOS Information Architecture

- Keep the current Friends tab as the feature home.
- Keep the existing Friends root header:
  - left: `Friends` title,
  - right: current `Manage` glass button.
- Keep the existing shared-shifts navigation path unchanged.
- Add messaging as a secondary action off each friend row instead of as a new root mode.
- Keep the existing top-right user menu in the navigation bar.
- Keep message navigation inside the same `NavigationStack` used by Friends so notification deep links can land directly in thread detail.

### Entry Points

- Replace the trailing chevron in the main `FriendCard` header row with a chat icon button.
- The main body tap on `FriendCard` still opens that friend's shared shifts.
- The trailing chat icon is a separate 44x44 tap target that opens chat.
- Tapping the chat icon:
  - opens the canonical thread if one already exists,
  - otherwise calls `get_or_create_direct_thread` and pushes thread detail immediately.
- Show the chat icon only when the friend is currently eligible for a DM or already has an existing thread.
- If the user is not eligible to start a new chat and there is no existing thread, do not show a disabled icon; omit the action entirely.
- Add a prominent `Message` action in friend profile surfaces where the user is already managing that person:
  - `FriendProfileView`
  - expanded friend rows in `ManageSharingSheet`
- Push notifications for `thread_message` open the Friends tab and push the target thread directly.

### Visual System

- Stay inside Tidex's existing iOS language:
  - semantic colors only,
  - `tidexGlass` for primary floating chrome,
  - card surfaces and shadows matching Friends and Wagey.
- Use `Color.tidexBackground` as the screen background for both the Friends list and thread detail.
- Use `Color.tidexSurfacePrimary` and `Color.tidexSurfaceSecondary` for cards, bubbles, and empty states.
- Use `Color.tidexBrandPrimary` for outgoing message emphasis, send button fill, unread dots, and active accents.
- Reuse the same avatar treatment already used in Friends:
  - rounded square avatar with concentric corner radius,
  - initials fallback when no image exists.
- Reuse Wagey's floating bottom chrome, scroll affordance behavior, and composer styling through shared components, but do not reuse Wagey's AI-specific copy or empty states.
- Do not introduce a new visual language just for chat. This should feel like a Tidex feature, not a separate product.

### Friend List Chat Entry UI

- `FriendCard` can no longer be a single full-card `Button`; it needs two explicit actions:
  - primary card tap for shared shifts,
  - trailing chat icon tap for messaging.
- The trailing icon uses `message.fill` or equivalent bubble icon, not a chevron.
- The chat action lives in the current top row where the chevron is today so the list layout stays familiar.
- The chat icon visually communicates state:
  - no unread messages: muted or secondary icon tint,
  - unread messages: brand tint plus a compact unread count badge,
  - `Should`: active thread open from push or deep link may show a temporary highlight ring on return.
- Do not add last-message preview text to the friend list in v1. The row should stay focused on the shared-shift preview.
- Do not add swipe actions or secondary menus to the friend list for chat in v1.

### Friend List Chat States

- Initial load with no local cache:
  - render the existing friend list loading state,
  - do not block friend list rendering on chat metadata.
- Chat thread summaries load in parallel with sharer previews and decorate rows once available.
- If chat metadata fails to load:
  - keep the friend list usable,
  - hide unread badges and fall back to the plain chat icon,
  - surface failures only when the user taps into chat and thread creation/open fails.
- If there are no eligible friends, do nothing extra in the main list; the current Friends empty state remains the source of truth.
- Manage sheet and friend profile still expose `Message` when eligible so users are not dependent on one entry point.

### Thread Detail UI

- Thread detail uses a standard pushed screen inside Friends.
- Navigation title is the counterpart's display name.
- `Should`: show the counterpart avatar in the title area on larger devices when space allows; fall back to text-only inline title on compact widths.
- The screen has three layers:
  - scrollable message timeline,
  - optional transient state banners,
  - pinned bottom composer.
- Open the thread at the bottom.
- If the user is already near the bottom, auto-scroll on new incoming/outgoing messages.
- If the user has scrolled up, keep scroll position stable and show a floating `jump to latest` button above the composer, matching Wagey behavior.

### Message Timeline Rules

- Base the thread screen on a generalized version of Wagey's `ChatMessageList`:
  - keep its scroll-to-bottom behavior,
  - keep its pinned-bottom tracking,
  - keep its bottom inset handling,
  - remove Wagey-specific empty state, streaming, suggestions, and assistant affordances.
- Use date separators for every new calendar day.
- Group consecutive messages from the same sender into clusters when sent within 3 minutes of one another.
- Inside a cluster:
  - tighten vertical spacing between bubbles,
  - show the timestamp only under the final bubble in the cluster.
- Outgoing messages:
  - right-aligned,
  - brand-filled bubble,
  - inverse text color.
- Incoming messages:
  - left-aligned,
  - surface-filled bubble,
  - primary text color,
  - subtle border when needed for contrast.
- Do not show per-message avatars in a 1:1 thread. The header avatar is enough.
- Bubble width cap:
  - text-only: about 72% of available width,
  - image-only or image + text: about 68% of available width.
- Day separators and timestamps use muted text and never compete with message content.
- Do not show read receipts in v1.

### Message Content Rules

- Text messages support links, phone numbers, and addresses through native data detection.
- Preserve line breaks in message bodies.
- Long unbroken text wraps rather than expanding the bubble off-screen.
- Image rendering:
  - show a rounded thumbnail in-line,
  - preserve aspect ratio,
  - cap display height to keep the thread readable,
  - place text below the image when a message has both.
- Tapping an image opens a full-screen media viewer.
- Full-screen image viewer:
  - darkened backdrop,
  - pinch-to-zoom,
  - drag-to-dismiss,
  - close button top-right,
  - no share/save actions in v1.
- System messages are supported by the schema but not rendered in the v1 client because v1 only writes `user` messages.

### Composer UI

- Reuse a generalized version of Wagey's `ChatInputField` and bottom chrome instead of inventing a second chat input style.
- Composer layout:
  - image picker button on the left,
  - expanding text field in the middle,
  - circular send button on the right.
- Keep the composer pinned above the keyboard and safe area.
- Text field behavior:
  - placeholder: localized `Message`,
  - min 1 line, max 5 visible lines,
  - `Return` inserts a newline,
  - send only by tapping the send button.
- Send button enables only when there is non-whitespace text or one selected image and there is no upload/send already in progress for the composer.
- Image picker:
  - Photos only in v1,
  - no camera action in v1.
- Attachment preview:
  - single selected image preview shown above the composer field,
  - removable with an `x` control,
  - show processing state while compression is happening.
- Clear the composer immediately after an optimistic send is inserted into local state.
- If image processing fails, keep the text intact and show an inline error banner above the composer.

### Typing, Sending, and Failure States

- Typing indicator appears as a compact three-dot pill just above the composer.
- Only show typing when:
  - counterpart typing broadcast is active,
  - thread is visible,
  - user is at or near the bottom of the timeline.
- Auto-clear typing 5 seconds after the last typing event.
- Optimistic send states for local messages:
  - `uploading`: image bubble shows progress overlay; text bubble shows subtle pending state.
  - `sending`: bubble remains in the timeline with reduced opacity.
  - `sent`: normal rendering.
  - `failed`: bubble remains in place with inline `Not sent` label and a retry affordance.
- Retrying a failed message reuses the same `client_id`.
- Do not drop failed messages out of the timeline.

### Mark Read and Unread Behavior

- Opening a thread marks it read through the latest loaded message after the initial payload is displayed.
- When new incoming messages arrive while the thread is open and the user is at the bottom, mark read automatically after render.
- If the user is scrolled away from the bottom, do not mark new messages read until they return to the bottom.
- The unread count shown on the friend-list chat badge is the number of counterpart messages newer than the caller's read marker.
- There is no per-message seen state in the UI.

### Accessibility and Motion

- All chat UI must support Dynamic Type without clipping or hidden actions.
- All touch targets remain at least 44x44 points.
- VoiceOver labels must describe:
  - friend-row chat actions with name and unread state,
  - message bubbles with sender and send state,
  - image attachments as photo messages.
- Color is never the only unread/failure signal:
  - unread also changes text weight and badge presence,
  - failure also shows text label.
- Respect Reduce Motion:
  - disable bouncey bubble insertions,
  - use simple fade transitions for typing and image preview changes.
- Keep animations short and purposeful:
  - subtle badge state changes on the friend-list chat icon,
  - fade/slide for jump-to-latest button,
  - subtle bubble insertion for optimistic sends.

### UI Exclusions for v1

- `Later`: reactions, replies, message edit/delete UI, in-thread search, pinned threads UI, archived threads UI.
- `Later`: camera capture, audio attachments, video attachments, generic file attachments.
- `Later`: group threads, org chat, and web messaging UI.

### Backend Data Model

- Add `public.threads` with:
  - `id`
  - `kind`
  - `created_by_user_id`
  - `title`
  - `avatar_url`
  - `metadata jsonb default '{}'`
  - `last_message_id`
  - `last_message_sender_id`
  - `last_message_at`
  - `created_at`
- Set `threads.kind` to `text check (kind in ('direct','room','feed'))`; v1 only creates `direct`.
- Add `public.direct_threads` with:
  - `thread_id`
  - `user_low_id`
  - `user_high_id`
  - `created_at`
  - unique on `(user_low_id, user_high_id)` to guarantee one DM per user pair
- Do not add a foreign key from `direct_threads` to a single `shift_shares` row.
- A DM belongs to the user pair, not to one directional share record, because:
  - eligibility can come from either share direction,
  - some pairs may have two reciprocal `shift_shares` rows,
  - old and new client behavior must not depend on which share row happened to create the thread.
- Add `public.thread_memberships` with:
  - `thread_id`
  - `user_id`
  - `role`
  - `status`
  - `joined_at`
  - `left_at`
- Use `role in ('owner','admin','member','poster','reader')` and `status in ('active','left')`; v1 DMs always create two `member/active` rows.
- Add `public.thread_user_state` with:
  - `thread_id`
  - `user_id`
  - `last_read_message_id`
  - `last_read_at`
  - `muted boolean default false`
  - `archived_at`
  - `updated_at`
  - primary key `(thread_id, user_id)`
- Keep `archived_at` in the schema for future use, but do not expose archive UI in v1.
- Add `public.messages` with:
  - `id`
  - `thread_id`
  - `sender_user_id`
  - `message_type`
  - `body null`
  - `client_id`
  - `reply_to_message_id null`
  - `created_at`
  - `edited_at`
  - `deleted_at`
  - `metadata jsonb default '{}'`
- Set `messages.message_type` to `text check (message_type in ('user','system'))`; v1 only inserts `user`.
- Keep `reply_to_message_id`, `edited_at`, and `deleted_at` for schema compatibility, but do not surface them in the v1 client.
- Add a message-validity check so a row cannot be inserted with both an empty body and zero attachments.
- Normalize text bodies before insert:
  - trim outer whitespace for validation,
  - preserve intentional interior whitespace and line breaks,
  - reject oversized bodies with an explicit server-side character limit.
- Add unique idempotency constraint on `messages(thread_id, sender_user_id, client_id)`.
- Add `public.message_attachments` with:
  - `id`
  - `message_id`
  - `attachment_index`
  - `kind`
  - `storage_bucket`
  - `storage_path`
  - `mime_type`
  - `byte_size`
  - `width`
  - `height`
  - `created_at`
- Set `message_attachments.kind` to `text check (kind in ('image'))`; v1 only stores images.
- Add key indexes on:
  - `thread_memberships(user_id, status)`
  - `threads(last_message_at desc, id desc)`
  - `messages(thread_id, created_at desc, id desc)`
  - `message_attachments(message_id, attachment_index)`

### Authorization, RLS, and Helper Functions

- Add SQL helper `public.can_access_thread(p_thread_id uuid)` returning true when the caller has an active membership in the thread.
- Add SQL helper `public.can_post_to_thread(p_thread_id uuid)` returning true when the caller is an active member whose role is not `reader`.
- Add SQL helper `public.can_create_direct_thread(p_other_user_id uuid)` returning true when either:
  - `(owner_id = auth.uid() and viewer_id = p_other_user_id)`, or
  - `(owner_id = p_other_user_id and viewer_id = auth.uid())`
  exists in `shift_shares` with the relation not hidden for eligibility and not abuse-blocked.
- Add SQL helper `public.is_user_pair_abuse_blocked(p_other_user_id uuid)` that resolves abuse-block state for the pair from `shift_shares.blocked_by_user_id` in either direction.
- Apply RLS so `threads`, `thread_memberships`, `thread_user_state`, `messages`, and `message_attachments` are selectable only when `can_access_thread(...)` is true.
- Do not allow direct client inserts into `threads`, `direct_threads`, `thread_memberships`, `messages`, or `message_attachments`; creation goes through RPCs so idempotency, relationship checks, and attachment validation stay centralized.
- Allow direct client upsert/update on `thread_user_state` only for `user_id = auth.uid()` and only when `can_access_thread(thread_id)` is true.
- Add a private Storage bucket `message-attachments`; do not use public URLs for chat images.
- Add Storage RLS policies so authenticated users can upload only into paths of the form `{thread_id}/{auth.uid()}/{attachment_id}.{ext}` when `can_post_to_thread(thread_id)` is true.
- Add Storage RLS policies so authenticated users can download only:
  - objects they uploaded themselves, or
  - objects that are already referenced by `message_attachments` in a thread they can access.
- Do not rely on path secrecy for unpublished uploads; unreferenced objects must stay unreadable to other thread members.

### RPCs and Public Interfaces

- Add `public.get_or_create_direct_thread(p_other_user_id uuid)`:
  - verify `can_create_direct_thread`,
  - normalize the user pair,
  - use `insert ... on conflict` or an equivalent retry-safe pattern so concurrent first-message flows cannot create duplicate direct threads,
  - create `threads`, `direct_threads`, `thread_memberships`, and `thread_user_state` atomically if missing,
  - return the canonical thread summary plus counterpart profile fields needed by the client.
- Add `public.list_my_threads(p_limit integer default 30, p_before_last_message_at timestamptz default null, p_before_thread_id uuid default null)`:
  - return thread summary,
  - unread count,
  - counterpart profile data for direct threads,
  - latest message preview,
  - paginate by `(last_message_at, id)` keyset rather than timestamp alone so ordering stays stable when timestamps collide.
- Use `list_my_threads` in iOS to decorate the main friend list with:
  - existing thread id,
  - unread count,
  - mute state,
  - last message metadata when needed for notifications and local cache.
- Add `public.list_thread_messages(p_thread_id uuid, p_limit integer default 50, p_before_created_at timestamptz default null, p_before_message_id uuid default null)`:
  - return canonical message rows with ordered attachment metadata,
  - paginate by `(created_at, id)` keyset rather than timestamp alone so back-pagination cannot duplicate or skip rows.
- Add `public.send_message(p_thread_id uuid, p_client_id uuid, p_body text, p_attachments jsonb default '[]')`:
  - validate posting rights,
  - normalize `p_body`,
  - reject requests where trimmed text is empty and there are no attachments,
  - enforce `0..4` attachments,
  - verify each attachment path belongs to the caller and thread and exists in Storage metadata,
  - run moderation before the message becomes visible to any recipient,
  - insert the message plus attachment rows in one transaction,
  - update `threads.last_message_*`,
  - return the canonical inserted payload.
- Add `public.mark_thread_read(p_thread_id uuid, p_through_message_id uuid)`:
  - verify the message belongs to the thread,
  - upsert `thread_user_state`,
  - move the read marker forward only; never allow a stale client to move it backward,
  - clear unread count for that caller through the supplied message.
- Add `public.set_thread_muted(p_thread_id uuid, p_muted boolean)` as a thin helper over `thread_user_state`.
- Make `can_access_thread(...)` and `can_post_to_thread(...)` pair-aware for direct threads:
  - if the thread's participant pair is abuse-blocked, keep read access to historical messages,
  - deny new posts into the thread,
  - deny any new direct-thread creation for that pair.
- Do not expose archive, pin, reply, or message mutation RPCs in v1.
- Return counterpart profile data from listing RPCs using the same pattern already used by sharing: read `auth.users` metadata and `user_settings.profile_picture_url` inside `SECURITY DEFINER` functions.

### Realtime, Presence, and Notifications

- Enable Realtime publication for `threads`, `messages`, and `thread_user_state`.
- Subscribe thread detail views to `postgres_changes` on `messages` filtered by `thread_id`.
- On message insert/update events, fetch the canonical payload by message id or reload the latest page so attachments and derived fields stay consistent.
- Subscribe the main Friends list chat-decoration state to `threads` and `thread_user_state` so unread badges update without polling.
- Client merge rules for Realtime events:
  - dedupe by server message id and local `client_id`,
  - treat Realtime as a freshness signal, not the sole source of truth,
  - run a latest-page resync after reconnect so transient disconnects do not leave holes.
- Use Realtime broadcast on channel `thread:{thread_id}` for `typing_start` and `typing_stop`.
- Broadcast payloads should be minimal:
  - sender user id,
  - event kind,
  - client timestamp.
- Auto-clear typing indicators client-side after 5 seconds without a refresh event.
- Add trigger `public.queue_thread_message_notification()` on `messages after insert`; enqueue one outbox row per active thread member except the sender.
- Skip push enqueue when the recipient has `thread_user_state.muted = true`.
- Set notification payload type to `thread_message` with:
  - `thread_id`
  - `message_id`
  - `thread_kind`
- Build notification copy as:
  - use trimmed body preview when present,
  - otherwise use localized `{sender} sent a photo` for image-only messages.
- Use idempotency key `thread_message:{message_id}:{recipient_id}` in `internal.notifications_outbox`.
- Do not suppress push notifications based on live presence in v1.

### Image Attachment Pipeline

- Reuse the existing direct-upload pattern rather than base64-posting images through the app server.
- iOS compresses off-main before upload; target max long edge `2048px`, preferred format `webp`, fallback `heic`, then `jpeg`.
- Accept:
  - `image/webp`
  - `image/heic`
  - `image/heif`
  - `image/jpeg`
  - `image/png`
- Set v1 hard limits to:
  - `1` image in the iOS composer,
  - `4` attachments max in the backend RPC,
  - `5 MB` max per uploaded object after compression.
- Upload the image first to Storage path `{thread_id}/{user_id}/{attachment_id}.{ext}` using the authenticated Supabase client.
- Because uploads land before `send_message` commits, unpublished objects must remain private through Storage RLS until a `message_attachments` row references them.
- Call `send_message` only after upload succeeds; pass attachment descriptors with:
  - `attachment_id`
  - `storage_path`
  - `mime_type`
  - `byte_size`
  - `width`
  - `height`
- On send failure after upload, keep the local pending message and retry with the same `client_id` and `attachment_id`; the RPC idempotency constraint prevents duplicate persisted messages.
- Add a cleanup job for orphaned uploads older than 24 hours that are still not referenced by `message_attachments`; implement it later as a service-role cleanup path. It is not blocking for v1 launch.

### iOS Architecture Changes

- Add a new Friends messaging feature area under `ios/TidexApp/Features/Friends/Messages/`.
- Extract shared chat UI primitives out of Wagey into a central location such as `ios/TidexApp/Shared/Chat/`.
- Do not reuse Wagey's `LocalConversation`; create dedicated SwiftData models for:
  - `LocalThread`
  - `LocalThreadState`
  - `LocalMessage`
  - `LocalMessageAttachment`
- Add a dedicated `MessagingRepository`; do not route chat through `SyncCoordinator` because chat needs optimistic writes and live subscriptions, not batch sync semantics.
- The repository owns:
  - friend-list thread summary loading,
  - thread detail pagination,
  - Realtime subscriptions,
  - optimistic local sends,
  - image upload,
  - retry,
  - read-state updates,
  - mute actions.
- Read from SwiftData first, then refresh from network.
- Keep view models `@MainActor` and inject repository dependencies.
- Shared chat UI extraction must centralize:
  - scroll container behavior from `ChatMessageList`,
  - bottom composer shell from `ChatInputField`,
  - jump-to-latest button behavior,
  - attachment preview presentation,
  - keyboard and bottom inset handling.
- Wagey should consume the shared chat primitives plus its own AI-specific layers.
- Friends chat should consume the same shared chat primitives plus a direct-message-specific bubble renderer and empty state.
- Reuse existing building blocks where it reduces risk:
  - avatar presentation from Friends,
  - cached image behavior patterned after `CachedAsyncImage`.
- Store attachments as arrays in local models and DTOs even though the v1 composer only allows one image.

### Localization and Copy Rules

- All user-visible copy must be added to the string catalog; no hardcoded UI strings in implementation.
- Key copy that must be explicitly localized up front:
  - `Message`
  - `Sent a photo`
  - `You:`
  - `Not sent`
  - thread empty-state title/body
  - retry, mute, unmute actions
- Keep copy short and plain. Chat should feel utility-first, not playful.

### App Review and UGC Compliance

- Treat Friends chat as user-generated content and design the feature to satisfy Apple App Review Guideline 1.2 from day one.
- Do not rely on review notes alone. The app itself must expose the necessary reporting, blocking, filtering, and contact surfaces.
- Assume Apple reviewers will actively test the chat flow, not just skim the metadata.
- The three most common rejection triggers to guard against are:
  - no in-app way to report a message or user,
  - no in-app way to block a user from further contact,
  - no visible moderation/support contact or legal surface for UGC concerns.

#### Minimum Apple-Safe Checklist

- The shipped build must include all of the following before App Store submission:
  - report message or report user,
  - block user,
  - privacy policy,
  - terms of service or community-rules surface,
  - developer contact for moderation or abuse concerns.
- Treat this list as launch-blocking for chat. If one item is missing from the shipped build, delay launch rather than hoping App Review notes will compensate.

#### Reviewer Behavior Assumption

- Expect reviewers to do at least the following in a test account:
  - send a message,
  - look for a report action from chat or profile,
  - look for a block action from chat or profile,
  - verify privacy policy, terms, and support/contact links are reachable in-app.
- The report and block actions must be discoverable without hidden gestures, debug menus, or external instructions.

#### Filtering Objectionable Material

- Add a server-side moderation gate to `send_message` so objectionable content is filtered before a message is persisted or delivered.
- Recommended v1 implementation:
  - use OpenAI `omni-moderation-latest` as the primary synchronous gate for both message text and image attachments,
  - add a child-safety image layer such as Microsoft `PhotoDNA` for known illegal-image matching before an image can be attached to a visible message,
  - if the child-safety image layer is not ready in time, remove image attachments from launch rather than shipping image chat with incomplete safeguards.
- Text moderation requirement for v1:
  - run every non-empty message body through a moderation service or rules engine before insert,
  - reject content that crosses the configured threshold,
  - return a user-safe error message that explains the message could not be sent.
- Image moderation requirement for v1:
  - every uploaded image attachment must be moderated before the message becomes visible to the recipient,
  - if moderation fails or flags the image, the message send must fail closed rather than publish first and clean up later.
- Keep a moderation result record for auditability with:
  - message `client_id` or upload `attachment_id`,
  - sender id,
  - thread id,
  - decision,
  - provider or rule version,
  - created timestamp.
- Do not surface moderation scores to end users in v1.
- Because image attachments are required for launch, moderation is launch-blocking work, not a follow-up item.
- V1 threshold policy:
  - fail closed on moderation provider errors or timeouts,
  - block immediately for sexual content involving minors, self-harm instructions, explicit threats, graphic violence, hateful harassment, spam bursts, and any known illegal-image hash match,
  - avoid a manual review hold state in the send path for v1; messages are either accepted or rejected synchronously.

#### Reporting Offensive Content

- Add a report flow from thread detail with two entry points:
  - long-press or context menu on an individual message,
  - thread header action sheet for reporting the user or the whole conversation.
- This is launch-blocking. If reviewers cannot find a report action in the shipped UI, expect a Guideline 1.2 rejection.
- Message report reasons in v1:
  - harassment or bullying,
  - sexual content,
  - hate or discriminatory content,
  - violence or threats,
  - spam,
  - other.
- Thread-level user report reasons in v1:
  - harassment or bullying,
  - spam,
  - inappropriate profile or conduct,
  - other.
- Persist reports in a dedicated backend table with:
  - reporter user id,
  - reported user id,
  - thread id,
  - optional message id,
  - reason,
  - optional free-text note,
  - status,
  - created_at,
  - reviewed_at,
  - reviewed_by.
- Default admin report workflow for v1:
  - `open`: newly created and awaiting triage,
  - `in_review`: actively being investigated,
  - `actioned`: moderation action taken or user contacted,
  - `dismissed`: reviewed and closed with no further action.
- Default admin actions for v1:
  - mark `in_review`,
  - mark `actioned`,
  - mark `dismissed`,
  - set or confirm abuse block on the reported user pair,
  - add internal reviewer notes,
  - open the linked thread context from the report.
- Send a support/admin notification when a report is created so the queue is not passive.
- Add a dedicated `Reports` tab in the admin panel before launch. A raw database table with no review UI is not enough.
- Reporting a user must still link the relevant thread so admins can assess surrounding context even when no single message is selected.

#### Blocking Abusive Users

- Add a messaging-specific block action in thread header actions and friend-management surfaces.
- This is launch-blocking. If reviewers cannot find a block action in the shipped UI, expect a Guideline 1.2 rejection.
- Blocking must do more than hide a row locally.
- Default block behavior for v1:
  - prevent future message sends in both directions,
  - hide the blocked user's typing and push notifications,
  - remove the chat icon entry point from the main friend list,
  - hide the blocked user's active profile and message entry surfaces where feasible,
  - preserve past messages in a read-only thread view.
- Service-level blocking applies across both chat and sharing access. It is one user action, not separate chat and sharing blocks.
- Do not reuse the existing `shift_shares.blocked` meaning for abuse blocks. In the current app that field behaves like `hidden from my view`.
- Backward compatibility requirement:
  - old iOS versions will continue reading and writing `shift_shares.blocked`,
  - new app versions must move to a new hide field such as `shift_shares.hidden`,
  - one-time copy is not enough; legacy `blocked` and new `hidden` must stay synchronized during the migration window.
- Migration plan for the existing hide behavior:
  - add `shift_shares.hidden boolean not null default false`,
  - backfill `hidden = blocked` for all existing rows,
  - add a database trigger so writes to either `blocked` or `hidden` keep the two fields in sync while legacy clients are still active,
  - update new iOS and web code to read/write `hidden`,
  - keep `blocked` as a legacy compatibility field until old client versions are retired,
  - only then remove or rename the legacy field in a later cleanup migration.
- Add a real abuse-block field to `shift_shares` such as `blocked_by_user_id uuid null`.
- `blocked_by_user_id` means the sharing relationship is abuse-blocked by that user, not merely hidden from one list.
- Blocking operations must record who initiated the abuse block by setting `blocked_by_user_id`.
- If the pair has reciprocal `shift_shares` rows, the block operation should update both rows consistently so chat and sharing checks resolve the pair as blocked regardless of direction.
- Thread creation, thread posting, sharing visibility, and notification delivery must all check the abuse-block state in addition to hide state.
- Closed policy decision for v1:
  - abuse blocking hides historical shared shifts and all future sharing access in both directions,
  - existing chat threads remain visible read-only for evidence and reporting context,
  - the blocker should not continue seeing the blocked user's shift history after the block is applied.

#### Published Contact Information

- Use the existing public support contact `contact@tidex.no`.
- Use the existing support page as the canonical public support destination:
  - `https://app.tidex.no/support`
- Use the existing public privacy policy as the canonical privacy destination:
  - `https://tidex.no/privacy`
- Add a visible `Safety and support` or `Report a problem` link in chat-related settings or thread actions that opens the support page or mail composer.
- This is launch-blocking. If there is no obvious moderation/support contact in the app, expect App Review risk even if the email exists elsewhere.
- Make sure the same contact information is visible in:
  - App Store listing support URL,
  - in-app settings or support surface,
  - any moderation/report confirmation copy that tells users how to follow up,
  - the App Store privacy policy link.

#### Terms and Legal Surface Requirements

- Update Terms of Service to explicitly prohibit harassment, bullying, hate, threats, spam, sexual exploitation, and other abusive use of chat or social features.
- Make Terms of Service and Privacy Policy reachable from inside the app in a support or legal surface that does not depend on onboarding.
- Add `Privacy Policy` and `Terms of Service` links to the chat support/report flow confirmation sheet or adjacent support surface so reviewers can find them without hunting through the app.

#### Reviewer Checklist

- Before submission, verify all of the following are discoverable in the shipped app build:
  - a report action exists from chat,
  - a block user action exists from chat,
  - Terms of Service mention acceptable behavior,
  - Privacy Policy is linked,
  - abuse reporting contact exists.
- Include these exact locations in App Review notes:
  - where to open the report flow,
  - where to block a user,
  - where to find Terms of Service,
  - where to find Privacy Policy,
  - where to find support contact info.

#### Operational Requirement

- Before App Store submission, define and document the review workflow for reports:
  - who receives them,
  - target first-response time,
  - how abusive accounts are blocked or suspended,
  - how evidence is retained.
- Abuse reports are handled by admins inside the admin panel `Reports` tab.
- Target first response time for abuse reports: less than 24 hours.
- Include this workflow in App Review notes so Apple can understand how moderation is handled.

### Closed Policy Decisions

- Admin report states for v1 are:
  - `open`,
  - `in_review`,
  - `actioned`,
  - `dismissed`.
- Default admin report actions for v1 are:
  - move between workflow states,
  - add internal notes,
  - open linked thread context,
  - set or confirm abuse block on the reported pair.
- Abuse blocking hides historical shared shifts and all future sharing access in both directions.
- Existing chat threads remain visible read-only after a block so users and admins retain evidence and reporting context.

### Web and Future-Scope Compatibility

- No web messaging UI is shipped in v1, but the schema stays generic enough for later web inbox and detail views.
- Future group chat adds more `thread_memberships` rows and starts creating `threads.kind = 'room'`; no storage or message-table redesign is needed.
- Future organization feeds add an org-scoped linkage table and access helper, then start creating `threads.kind = 'feed'`; existing `messages`, `attachments`, `thread_user_state`, Realtime, and push logic remain unchanged.
- The only expected future additions for org features are new access tables/helpers and possibly extra membership derivation logic; DM storage remains stable.

### Delivery Phases

- Phase 0: prerequisite migration hardening
  - add `shift_shares.hidden`,
  - add `shift_shares.blocked_by_user_id`,
  - backfill and dual-write/sync `blocked` and `hidden`,
  - update existing sharing readers and writers in iOS, Next.js, and SQL helpers so new code no longer treats `blocked` as the long-term source of truth.
- Phase 1: backend core
  - ship messaging tables, Storage bucket, helper functions, RPCs, and RLS,
  - add SQL tests for auth, pagination, idempotency, and block behavior,
  - keep the feature dark with no user entry points yet.
- Phase 2: iOS infrastructure
  - add local models, repository, Realtime plumbing, and shared chat UI extraction from Wagey,
  - verify Wagey still renders correctly after shared component extraction,
  - add repository tests before wiring navigation.
- Phase 3: user-facing messaging
  - add friend-list entry points, thread detail, composer, attachments, notifications, and deep links,
  - add report/block/support surfaces required for App Review,
  - add UI tests for navigation, retry, unread, report, and block flows.
- Phase 4: rollout and launch
  - enable behind a server-controlled feature flag,
  - dogfood with the primary developer account `032d8c2a-9af6-4777-99f0-24e2c4058bf3`,
  - monitor metrics and moderation/report operations before wider release.

### Observability and Rollout Controls

- Add a server-side feature flag for Friends messaging so UI entry points, send RPCs, and push handling can be disabled without a new client build.
- Add structured logs or audit records for:
  - direct-thread creation,
  - send failures,
  - moderation rejects,
  - report creation,
  - abuse-block actions.
- Track launch health metrics at minimum:
  - thread creations per day,
  - successful sends vs failed sends,
  - median upload time,
  - moderation reject rate,
  - report volume,
  - push enqueue failures.
- Add at least one kill switch that can disable image attachments independently of text messaging if moderation or Storage issues appear during rollout.

### Test Plan

- SQL/RLS tests for `get_or_create_direct_thread`:
  - allowed with either active share direction,
  - denied when no share exists,
  - denied when the only share is hidden or abuse-blocked,
  - concurrent create calls still yield one canonical direct thread.
- SQL/RLS tests for reads:
  - non-members cannot select `threads`,
  - non-members cannot select `messages`,
  - non-members cannot select `message_attachments`,
  - non-members cannot download Storage objects,
  - blocked users cannot read newly restricted sharing or messaging data according to the chosen block policy.
- SQL tests for `send_message`:
  - text-only,
  - image-only,
  - text-plus-image,
  - empty body plus zero attachments rejected,
  - body over `2000` normalized characters rejected,
  - invalid storage path,
  - wrong sender prefix,
  - too many attachments,
  - duplicate `client_id`,
  - retry semantics.
- Storage-policy tests:
  - valid upload path allowed,
  - wrong thread path denied,
  - wrong sender path denied,
  - non-member download denied.
- Trigger tests for `queue_thread_message_notification`:
  - sender excluded,
  - muted recipient skipped,
  - image-only body copy correct,
  - idempotency key correct.
- Realtime acceptance tests:
  - new message appears in thread detail without reload,
  - friend-list unread badge updates live,
  - typing indicator appears and disappears without DB writes,
  - reconnect triggers a catch-up refresh without duplicating messages.
- Moderation tests:
  - objectionable text is rejected before insert,
  - flagged image upload cannot be attached to a visible message,
  - moderation provider failure fails closed in v1.
- Report-flow tests:
  - message report creates the correct backend record,
  - thread/user report creates the correct backend record,
  - report confirmation UI is shown,
  - admin/support notification is enqueued.
- Blocking tests:
  - blocked users cannot create new direct threads,
  - blocked users cannot send new messages into an existing thread,
  - blocked users no longer generate push notifications for the blocker,
  - blocked friend rows no longer show the chat entry point,
  - blocked threads remain visible read-only.
- iOS repository tests:
  - optimistic send inserts local pending message immediately,
  - failed upload/send remains retryable,
  - mark-read updates unread badge state,
  - pagination appends older messages without reordering existing ones,
  - equal-timestamp pages do not duplicate or skip messages,
  - stale read acknowledgements do not move the marker backward,
  - Realtime echoes reconcile with optimistic local messages instead of rendering duplicates.
- iOS UI tests:
  - friend card main tap still opens shared shifts,
  - tapping the trailing chat icon opens the correct thread,
  - unread badge appears on the friend-list chat icon,
  - image-only message renders correctly,
  - failed message shows retry affordance,
  - report message flow is reachable from thread detail,
  - report user flow links the thread context for admins,
  - block user flow removes the friend-list chat entry and leaves the existing thread read-only,
  - push deep link opens the correct thread from the Friends tab.

### Launch Defaults

- Direct messages are permitted on any active share relationship that is not hidden for eligibility and not abuse-blocked; mutual sharing is not required.
- V1 exposes direct threads only; `room` and `feed` kinds are reserved for later.
- V1 iOS composer supports one image, but backend and local models support multiple attachments without schema changes.
- Chat attachments are private assets; no public bucket and no public URL strategy will be used.
- Push notifications are always sent for new messages unless the recipient muted the thread.
- No organization schema is added now; future organization support attaches new access rules to the existing thread core rather than changing message storage.
- V1 moderation fails closed for both text and image sends.
- V1 launches behind a feature flag and is enabled first for internal testing accounts before broader rollout.
- V1 uses OpenAI `omni-moderation-latest` as the primary text and image moderation gate, plus a known-illegal-image matching layer such as Microsoft `PhotoDNA` for image safety.
- V1 message bodies are limited to `2000` normalized characters after trimming outer whitespace; iOS validation and RPC validation must match exactly.
