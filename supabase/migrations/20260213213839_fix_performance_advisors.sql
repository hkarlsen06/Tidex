
-- Add missing index for foreign key wage_snapshots.tariff_type_id
CREATE INDEX idx_wage_snapshots_tariff_type_id
  ON public.wage_snapshots (tariff_type_id);

-- Drop unused indexes on public schema
DROP INDEX IF EXISTS public.idx_feedback_created_at;
DROP INDEX IF EXISTS public.idx_feedback_responded_by;
DROP INDEX IF EXISTS public.idx_feedback_user_id;
DROP INDEX IF EXISTS public.idx_recurring_shifts_user_active;
DROP INDEX IF EXISTS public.idx_series_shifts_user_id;

-- Drop unused indexes on internal schema
DROP INDEX IF EXISTS internal.notifications_outbox_created_at_idx;
DROP INDEX IF EXISTS internal.idx_ntw_shift_operations;
DROP INDEX IF EXISTS internal.tariff_versions_effective_date_idx;
;
