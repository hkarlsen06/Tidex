# Feature TODO: Clock Flow, Payslip Analysis, Workplaces

Last updated: 2026-02-28
Owner: Product + iOS
Status: Draft, validated against current code contracts

Related plan:
- [MULTI_JOB_PLAN.md](../MULTI_JOB_PLAN.md)

## Scope in this document

This TODO covers:
- Feature 1: Clock in / clock out flow (no break button)
- Feature 3: Wagey payslip analysis mode
- Feature 4: Multi-workplace support with color coding and filtering

This document is intentionally implementation-aware for the current local-first architecture.

## Verified current contracts (2026-02-24)

- Shift data/sync currently uses these Supabase tables: `user_shifts`, `recurring_shifts`, `wage_snapshots`, `user_settings`, `notification_preferences`, `profiles`.
- Current shift contracts require closed intervals (`start_time` + `end_time`):
  - iOS `ShiftRow`, `StoredShift`, `ShiftActivityAttributes`
  - widget/watch/live-activity rendering paths
- There is no active-shift table/RPC today (`active_shifts`, `startActiveShift`, etc. do not exist yet).
- Wagey currently streams through `POST /api/chat` with `routerStreamKey: "wagey"`.
- There is no dedicated payslip route/stream key/toolset yet.
- Current Wagey attachment path is image-only (base64 image blocks). No PDF/document upload pipeline exists today.
- There is no `workplaces` table or `workplace_id` field in current runtime schema.
- Multi-workplace backend work must align with [MULTI_JOB_PLAN.md](../MULTI_JOB_PLAN.md) (`jobs` + `job_id`) unless that plan is intentionally replaced.

---

## Feature 1: Clock in / Clock out flow

### Plan update (2026-02-28): normal ongoing shift rule

Accepted update: clock buttons now handle two distinct active sources:

1. Temporary clock session exists (new feature flow).
2. Persisted normal shift is currently ongoing (`now` between stored `start_time` and `end_time`).

Updated behavior matrix:

| State | `Clock in` | `Clock out` |
|-------|------------|-------------|
| No active shift | Enabled | Disabled |
| Temporary clock session active | Disabled | Enabled, opens clock-out review sheet, then saves new shift |
| Persisted normal shift ongoing | Disabled | Enabled, immediately ends that shift at `now` (no review sheet) |

### Product intent

- Add two buttons under `TotalCard`: `Clock in` and `Clock out`.
- Only one is active at a time.
- A running shift should feel native across surfaces:
  - Dashboard featured shift card behaves as ongoing shift
  - Live Activity behaves as ongoing shift
  - Widgets show elapsed time when end time is unknown
- Clocked shift is temporary until clock-out is confirmed.
- On clock-out, show a review sheet where user can edit start/end before final save.

### Current baseline in code (verified)

- Dashboard already supports ending an ongoing persisted shift (`endShiftNow`) from featured shift actions.
- Ongoing-shift detection currently means "now is between `start_time` and `end_time`" on normal shift rows.
- Unknown-end active shifts are not currently represented in shared app/widget/watch/live-activity models.

### Proposed UX flow

1. User taps `Clock in`.
2. App creates a temporary active shift record with start timestamp and no end.
3. UI immediately switches to "ongoing shift" state:
   - `Clock in` disabled
   - `Clock out` enabled
   - featured card and countdown reflect active shift
   - temporary shift is visible in calendar/list with dashed outline (not solid)
   - Live Activity starts if enabled
   - widget timeline updates
4. User taps `Clock out`.
5. If active state is temporary, app opens `Clock-out review sheet`:
   - prefilled start and end
   - allow edit for accuracy
   - final `Save shift` action
6. On save, app converts temporary record into normal persisted shift and triggers sync.
7. Temporary active shift is cleared.
8. If active state is persisted-normal-shift, app skips review and directly sets end time to `now` via existing `endShiftNow` path.

### Data and architecture TODO

- [ ] Define temporary active shift model (local-only, survives app restart)
- [ ] Decide storage location:
  - SwiftData `LocalActiveShift` model
  - or dedicated local persistence (UserDefaults/app group) if simpler
- [ ] Add new local-only active-shift repository/service abstraction (new API surface)
- [ ] Keep temporary active shift out of `user_shifts` until commit (current schema/UI assumes `end_time` exists)
- [ ] Commit through existing persisted path (`ShiftsRepository.createShift(...)` + normal sync)
- [ ] Ensure only one active shift per user at a time
- [ ] Add explicit active-state enum in `DashboardViewModel`:
  - `.none`
  - `.temporary(activeSession)`
  - `.persisted(ongoingShift)`
- [ ] Derive button enablement and action routing from active-state enum
- [ ] Route `Clock out` by active state:
  - `.temporary` -> clock-out review sheet flow
  - `.persisted` -> `endShiftNow` immediate end flow
- [ ] Disable `Clock in` when:
  - a temporary active shift already exists
  - another currently active persisted shift exists
- [ ] Add crash-safe recovery on app launch
- [ ] Add deep-link and tab state handling while active shift exists
- [ ] Keep repository/API impact minimal:
  - no new public API beyond previously planned idempotent create path with optional `shiftId`
- [ ] If unknown-end active shifts are required across surfaces, first migrate shared model contracts:
  - `StoredShift`
  - `ShiftActivityAttributes`
  - watch/widget DTOs that currently require end time

### UI TODO

- [ ] Add button row under `TotalCard` (state driven)
- [ ] Add active-state visuals and haptics
- [ ] Add dashed-outline visual treatment for temporary active shift in list and calendar
- [ ] Add clock-out review sheet
- [ ] Add validation in review sheet:
  - end must be after start (allow overnight logic)
  - max duration guardrails
- [ ] Add conflict handling if shift overlaps existing shifts

### Surface integration TODO

- [ ] Dashboard featured shift card supports active temp shift
- [ ] Live Activity behavior split by active state:
  - temporary: open-ended count-up activity
  - persisted: keep current countdown-to-end behavior
- [ ] When persisted ongoing shift is ended from `Clock out`, existing `endShiftNow` + Live Activity end path stays authoritative
- [ ] Widget storage supports active temp shift with no end time (after app-group model migration)
- [ ] `Shifts` tab can display temporary active shift state if needed
- [ ] Notification scheduling behavior defined for active temporary shift

### Sync and reliability TODO

- [ ] Temp shift remains local until commit
- [ ] Commit writes normal shift through repository and marks dirty
- [ ] Handle offline clock-out commit retries
- [ ] Ensure idempotent commit if app is terminated during save

### Acceptance criteria

- [ ] User can start and stop shift from dashboard without opening Add Shift
- [ ] Ongoing shift state is consistent across app, live activity, and widget
- [ ] Temporary active shift is visibly differentiated (dashed outline) before commit
- [ ] Clock-out review allows corrections before save
- [ ] Final saved shift appears in Shifts and payroll calculations
- [ ] No duplicate shifts from repeated clock-out taps or retries
- [ ] When persisted ongoing shift exists, `Clock in` is disabled
- [ ] When persisted ongoing shift exists, tapping `Clock out` immediately ends that shift at current time
- [ ] Temporary active session still uses review-sheet flow without regression
- [ ] Persisted and temporary states never drive conflicting clock button actions

### Decisions confirmed (2026-02-24)

- `Clock in` starts immediately at current time; no pre-start backdate flow.
- Start time correction happens in clock-out review.
- If shift crosses midnight, keep it as one shift.
- Clock-out review allows editing start/end only (no date edit).
- Custom supplements are edited only after save (not in clock-out review).
- Active temporary shift is visible before commit with dashed outline.
- `Clock in` is disabled while temporary active shift exists or another active shift exists.
- Temporary shift is lost on logout.
- No separate overlap flow at clock-in; gating is via active-shift button state.

### Decisions confirmed (2026-02-28 update)

- Clock action handling is state-routed with explicit precedence:
  - temporary session state
  - persisted ongoing shift state
  - none
- Persisted ongoing shift clock-out is immediate (no review sheet), using `endShiftNow`.

### Open questions

1. None (V1 decisions locked)

---

## Feature 3: Wagey payslip analysis mode

### Product intent

- Add a separate Wagey mode for payslip analysis.
- User uploads payslip document.
- Wagey analyzes deeply using dedicated tools and system prompt.
- Result should compare expected vs actual and explain differences.
- User experience should remain a normal Wagey conversation, with extra hidden setup/context steps.

### Proposed mode shape

- New entry point: `Analyze payslip` in Wagey UI
- Separate payslip-analysis context under the hood, while keeping normal chat UX
- Dedicated tool access and stricter output format
- Conversation can remain free-form, but should still cover:
  - detected payslip values
  - expected pay estimate from app data/tools
  - variance summary and likely causes

### Current baseline in code (verified)

- Wagey uses one chat endpoint (`POST /api/chat`) and one stream key (`wagey`).
- No dedicated payslip mode route/stream/toolset exists yet.
- iOS message attachments currently support images only (no PDF picker/upload path).
- iOS conversation persistence is local (`LocalConversation` in SwiftData), not a dedicated Supabase conversation table.

### Data access and security TODO

- [ ] Audit and document current Wagey data access scopes
- [ ] Define minimum required data for payslip mode
- [ ] Define how payslip mode is routed on the current chat contract:
  - add a new stream key (for example `wagey_payslip`) in `next/lib/chat/router.ts`, or
  - add a mode field handled by the existing `wagey` stream
- [ ] Add explicit consent gate for document analysis
- [ ] Enforce ephemeral file policy for any new uploaded files (no existing payslip file store today)
- [ ] Keep conversation history in Wagey as normal conversation history
- [ ] Add PII redaction strategy for logs and analytics

### Ingestion and parsing TODO

- [ ] Decide V1 format scope (image-only vs PDF+image); current implementation supports image input only
- [ ] If PDF support is required, implement a new PDF upload + extraction pipeline (new API/storage contract)
- [ ] Add OCR/text extraction and normalization
- [ ] Build payslip field extraction schema
- [ ] Add parser confidence scoring and validation
- [ ] Handle multi-page and low-quality scans

### Wagey tool/prompt TODO

- [ ] Add payslip-mode system prompt in the actual chat router flow
- [ ] Add restricted payslip toolset (new tools; none exist yet for payslip extraction)
- [ ] Add comparison tool against local payroll engine outputs
- [ ] Add deterministic calculation fallback when model confidence is low
- [ ] Add structured response format for UI rendering

### UI TODO

- [ ] Add payslip mode entry in Wagey
- [ ] Add upload UI with progress, errors, retry
- [ ] Keep result experience inside normal chat flow (no forced structured report screen)
- [ ] Add "report issue" action on incorrect extraction

### Acceptance criteria

- [ ] User can upload a payslip and receive clear analysis in normal chat flow
- [ ] Analysis includes expected vs actual comparison
- [ ] Privacy controls are explicit and reversible
- [ ] Failures produce clear next actions
- [ ] Feature is gated to paid users

### Decisions confirmed (2026-02-24)

- Payslip files are deleted after analysis.
- Conversation history is still stored in Wagey like normal conversations.
- Feature is paid-tier only.
- V1 is not region-locked; it compares payslip content against data from app tools.
- No dedicated extracted-fields correction form; user corrects Wagey via conversation.
- Payslip analysis uses only user's own data/tools (no friends/sharing data).
- No dedicated export/share flow for payslip mode in V1; existing chat copy actions are sufficient.

### Open questions

1. None (V1 decisions locked)

---

## Feature 4: Multi-workplace support

### Product intent

- Support multiple workplaces/jobs with clear visual separation.
- First-time setup asks user to assign colors.
- On add-shift flow, before final add+navigate, show workplace picker sheet.
- Show workplace colors in calendar/list.
- Add filtering by workplace in shifts list (and likely calendar).

### Backend naming contract (must follow)

- UI copy can use "Workplace", but backend/data contract should use `Job`/`job_id` (per [MULTI_JOB_PLAN.md](../MULTI_JOB_PLAN.md)).
- Current codebase does not have `workplaces`/`workplace_id`.
- Current sync models (`SyncShiftRow`, `SyncRecurringShiftRow`, `SyncWageSnapshotRow`) also do not include `job_id` yet.

### Proposed UX flow

1. User sets up first workplace (name + color).
2. User creates additional workplace(s) with required color.
3. During Add Shift submit:
   - if user has 2+ workplaces, show workplace selection sheet with color coded options
   - user picks workplace
   - shift is saved with selected workplace (`job_id` in backend)
   - app navigates to Shifts as today
4. In Shifts tab:
   - list rows and calendar markers include workplace color
   - user can filter by one/many workplaces

### Data model TODO

- [ ] Add `Job` (`workplace` in UI) entity/table:
  - id
  - user_id
  - name
  - color
  - is_default / sort_order
  - created_at / updated_at / deleted_at / revision
- [ ] Add `job_id` to `user_shifts`, `recurring_shifts`, and `wage_snapshots` (not `workplaceId`)
- [ ] Make `job_id` mandatory for all newly created shifts after migration
- [ ] Define migration strategy: create default job per user, backfill `job_id`, install DB trigger fallback for missing `job_id`, then enforce NOT NULL
- [ ] Keep legacy compatibility: mirror `payroll_day`, `half_tax_month`, and `monthly_goal` between default job and `user_settings` during migration window
- [ ] Move payroll-engine-dependent settings to job scope per `MULTI_JOB_PLAN.md` (without removing legacy reads in V1)
- [ ] Add sync schema/model updates and migrations for all affected iOS sync row/local model types

### Add/Edit flow TODO

- [ ] Add workplace setup entry point in onboarding/settings
- [ ] Add workplace picker sheet at Add Shift submission point (only when 2+ workplaces exist)
- [ ] Add workplace selector in shift edit sheet
- [ ] Add recurring shift editor workplace support
- [ ] Enforce one-workplace-per-recurring-pattern (no per-occurrence workplace override)
- [ ] Handle deleted/archived workplace references gracefully
- [ ] Archived workplaces are hidden from Add Shift workplace picker

### Visualization and filters TODO

- [ ] Calendar day cell outline rendering:
  - single workplace day: one outline color
  - mixed workplaces day: split outline top-to-bottom into multiple colors
  - top-most segment = earliest shift workplace color
  - bottom-most segment = latest shift workplace color
  - include all workplaces present that day
- [ ] Shift list rows show workplace color badge
- [ ] Add filter UI in list view (single and multi-select)
- [ ] Reset workplace filters each session (no persistence across app launches)

### Payroll/analytics TODO

- [ ] Ensure totals remain correct with workplace/job dimension
- [ ] Ensure all payroll-engine-dependent settings are resolved per job
- [ ] Add workplace breakdown in stats (optional V1 or V1.1)
- [ ] Ensure exports include workplace columns

### Acceptance criteria

- [ ] User can create and manage multiple workplaces
- [ ] Every new shift can be assigned to a workplace (`job_id` in backend)
- [ ] Workplace colors are visible and consistent in list/calendar
- [ ] User can filter shifts by workplace
- [ ] Existing shift behavior remains stable for users with one workplace
- [ ] Filters only affect Shifts list in V1
- [ ] Pre-multi-job app versions remain functional against migrated schema (legacy writes without `job_id` still work)

### Decisions confirmed (2026-02-24)

- Workplace selection is mandatory.
- Workplace picker appears when user has 2+ workplaces.
- Payroll-engine-dependent settings should be per workplace (full scope).
- V1 filters affect only Shifts list.
- Workplaces support both archive and delete; archived workplaces are hidden from Add Shift picker.
- Recurring pattern and all its virtual shifts belong to one workplace (no per-occurrence override).
- Mixed-workplace day cell outlines are split top-to-bottom from earliest shift color to latest.
- Workplace filters reset each session.

### Open questions

1. None (V1 decisions locked)

---

## Cross-feature dependencies

- [ ] Data model migrations and sync contracts must be planned together
- [ ] Backwards-compatibility DB layer (default job assignment + settings mirror) must ship before app versions that depend on `job_id`
- [ ] Widget and Live Activity updates should be tested against active shift + workplace/job metadata
- [ ] Export and Wagey should align on new fields (`job_id`, workplace label, active shift semantics)
- [ ] Notification strategies should be reviewed for active shifts and workplace context

## Suggested implementation order

1. Clock in/out flow foundation (data + state sync across surfaces)
2. Workplace/job data model and shift assignment (`jobs` + `job_id`)
3. Workplace colors and filters in Shifts UI
4. Wagey payslip mode (after data access audit and privacy decisions)

## Decision log

- [x] Clock flow: immediate clock-in, review on clock-out, one cross-midnight shift, dashed temporary UI, supplements editable only after save, logout drops temporary shift
- [x] Payslip mode: paid-tier, ephemeral files, normal Wagey conversation history, own-account tools only, no dedicated export flow
- [x] Workplaces: mandatory workplace assignment, picker for 2+, per-workplace payroll settings, archive+delete support, recurring pattern locked to one workplace, mixed-day split outline, session-only filters (backend field name: `job_id`)
- [x] Multi-job rollout must keep old clients functional via DB compatibility layer (missing `job_id` fallback + mirrored legacy settings)
