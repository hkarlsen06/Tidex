-- Drop unused indexes that are structurally redundant with indexes that are
-- actively used by current query paths.
--
-- Kept intentionally:
-- - Single-column FK support indexes, even when currently unused.
-- - Rare admin/moderation indexes.
-- - Partial uniqueness/lookup indexes used to enforce queue coalescing.

-- Exact duplicate of the primary key on public.user_settings(user_id).
DROP INDEX IF EXISTS public.idx_user_settings_user_id;

-- Current active user-shift date access uses
-- idx_user_shifts_user_active_shift_date_desc (user_id, shift_date DESC, id)
-- WHERE deleted_at IS NULL. These narrower/older variants are unused.
DROP INDEX IF EXISTS public.idx_user_shifts_user_date_active;
DROP INDEX IF EXISTS public.idx_user_shifts_user_date_range;

-- Redundant with notifications_outbox_pending_due_at_id_idx, which matches the
-- pending queue claim ORDER BY due_at path and is actively used.
DROP INDEX IF EXISTS internal.idx_outbox_due;

-- Redundant with idx_wage_snapshots_user_active_from_date_desc for active
-- per-user wage snapshot lookup paths.
DROP INDEX IF EXISTS public.idx_wage_snapshots_user_date_active;
