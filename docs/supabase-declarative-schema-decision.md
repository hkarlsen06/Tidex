# Tidex declarative schema decision

Read before reconsidering declarative schema adoption or planning migration-history repair. This preserves the recorded evaluation; revalidate dated tool behavior before any future cutover. Paths are repository-relative.

### Declarative schema adoption is deferred

Tidex evaluated Supabase declarative schemas with CLI 2.109.1 on 2026-07-24
and must remain migration-only for now:

- Keep `[db.migrations].schema_paths = []`.
- Do not create or commit `supabase/schemas/`, enable schema paths, or add a
  pg-delta drift CI gate until the prerequisites below are complete.
- The committed migration history is not a reconstructable foundation.
  `20260311193000_schema_baseline.sql` starts from pre-existing core tables and
  is internally out of dependency order: it defines sharing functions that
  reference `user_settings.monthly_goals_by_month` before adding that column.
  A clean reset or shadow database therefore cannot establish a trustworthy
  declarative baseline.
- Do not add a naïve earlier-dated bootstrap migration. The self-hosted production
  database would treat it as unapplied during the next migration push.
- Git history contains a useful deleted `00000000000000_schema.sql` plus
  January 2026 migrations, but they are not safe to restore verbatim. The
  snapshot omits `feedback`, `notification_preferences`,
  `shift_shares.notification_frequency`, and
  `wage_snapshots.tariff_type_id`; two deleted migrations also share version
  `20260130120000`.
- A 2026-07-24 read-only dump of the then-hosted production `public,internal`
  schemas, advanced through the
  four pending forward migrations and preceded by explicit hand-written
  prerequisites for the seven required user-lane extensions, replays and
  resets cleanly in disposable stacks. An independent snapshot replay produced
  a byte-for-byte identical 485 KiB dump (SHA-256
  `21134dc08b0c94c4897b98153303c52e1580bc028c76c64e82d696da7602d08e`)
  after an explicit post-dump revoke preserved the intentional denial on
  `user_entitlements`. Auth, Storage, cron, Realtime, event-trigger, PGMQ,
  extension, and default-ACL inventories also match exactly. A fail-closed
  guard rejects replay over existing user tables and still allows a clean
  reset. This proves the current-state snapshot plus permanent hand-written
  lanes is a viable foundation candidate; it does not make the existing
  migration chain or production cutover safe.
- `supabase/sql/` has been reconciled for currently deployed function and view
  intent. Retired sharing and notification-queue sources were removed, the 11
  previously remote-only definitions were exported, and one forward migration
  captures all 45 functions and two views that lacked active CREATE history.
  Their definitions, ACLs, comments, and view options match the captured
  production catalog by exact hashes after disposable replay. A separate forward migration
  reconciles the three intentionally newer function definitions. Intentional
  future-state sources under `supabase/todo-migrations/` remain outside the
  active lane and differ from the captured production state by design.
- Read-only managed-schema inventory found `on_auth_user_created`,
  `ensure_rls`, three Storage buckets, 15 Storage policies, six cron jobs, four
  Realtime publication tables, the `stripe_sync_work` PGMQ queue, and Vault
  entries named `supabase_url` and `service_role_key`. Forward migrations now
  capture the Auth/event triggers, extension prerequisites, queue existence,
  canonical `profile-pictures` bucket/four policies, and removal of nine
  legacy avatar aliases. Queue messages and Vault values are runtime or secret
  data and must never be copied. The captured production `postgres` default
  ACLs grant broad privileges in `public` and `storage`; preserve them only in the reviewed
  privilege lane and revisit them against Supabase's explicit-grant rollout.
- The declarative pg-delta gate currently fails even for identical states. An
  ordered temporary schema build needed the extension prerequisite SQL plus
  explicit privilege/event-trigger inputs. With the exact same snapshot on the
  migration and declarative sides, `--use-pg-delta` still proposed destructive
  drop/recreate operations for six messaging tables, related indexes, and four
  functions. `--use-migra` returned no changes, and independent dumps were
  byte-identical, proving the pg-delta plan is a false positive. This is the
  active adoption blocker; related destructive dependency replacement is
  tracked in `supabase/pg-toolbelt#280`, and the clean-room breaking-alpha
  rewrite is still open in PR `#299`.
- Use exact read-only catalog/dump inventories for production-state comparison.
  Current declarative `db diff` documentation compares schema files with
  migrations, not the live database. CLI 2.109.1's explicit linked-to-URL form
  also returned an empty result with a deliberate probe table, while the
  linked-to-local form stalled behind legacy IPv6/link metadata; neither is
  valid live-drift evidence.
- The public-alpha `supabase db schema declarative sync` interface must not be
  used. CLI 2.109.1 still exposes it, but the current documented evaluation
  workflow is `supabase db diff` with `schema_paths`, followed by review and
  local migration application. pg-delta is the documented default; the
  installed CLI also confirms the explicit `--use-pg-delta` flag is supported.
- DML/backfills, Storage buckets, cron, extensions, publications, privileges,
  managed-schema objects, renames, and destructive/data-dependent transitions
  stay in reviewed hand-written migrations even after a future adoption.

Reconsider adoption only after all of these are true:

1. A production-safe, reconstructable foundational migration history exists.
2. `supabase/sql/` has been reconciled with current deployed intent.
3. Remote-only Auth and Storage objects have been exported and explained.
4. Migration-built, declarative-built, and production schemas round-trip with zero
   unexplained pg-delta output and matching exact catalog inventories.
5. Clean reset, lint, representative tests, advisors, and a disposable
   generated-migration trial pass.

Any eventual history cutover must be coordinated directly against the
self-hosted production database on one-s. First deploy all ordinary forward
migrations and regenerate the snapshot from that exact state. Create the new
snapshot with `supabase migration new`, add a generic fail-closed
nonempty-`public`/`internal` guard, and append the explicit privilege
reconciliation. Preserve current default-ACL behavior during the history
cutover; change privilege policy only in a separate reviewed migration.
Prove the snapshot from scratch, archive old applied migration files
byte-for-byte outside the active migration directory, then use
`supabase migration repair --db-url "$TIDEX_PROD_DB_URL"` to mark the old
versions reverted and the snapshot version applied. Migration repair changes tracking only, so the snapshot SQL
must never run on the populated production database. Verify tracking rows
read-only before the next explicit production migration push.
This is a future production operation and must not be inferred from routine
schema work.
