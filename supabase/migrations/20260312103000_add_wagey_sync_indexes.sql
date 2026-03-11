BEGIN;

CREATE INDEX IF NOT EXISTS idx_jobs_user_updated_at_id
  ON public.jobs (user_id, updated_at, id);

CREATE INDEX IF NOT EXISTS idx_jobs_user_active_sort_created
  ON public.jobs (user_id, sort_order, created_at)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_user_shifts_user_updated_at_id
  ON public.user_shifts (user_id, updated_at, id);

CREATE INDEX IF NOT EXISTS idx_user_shifts_user_active_shift_date_desc
  ON public.user_shifts (user_id, shift_date DESC, id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_recurring_shifts_user_updated_at_id
  ON public.recurring_shifts (user_id, updated_at, id);

CREATE INDEX IF NOT EXISTS idx_recurring_shifts_user_active
  ON public.recurring_shifts (user_id, id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_wage_snapshots_user_updated_at_id
  ON public.wage_snapshots (user_id, updated_at, id);

CREATE INDEX IF NOT EXISTS idx_wage_snapshots_user_active_from_date_desc
  ON public.wage_snapshots (user_id, from_date DESC, id)
  WHERE deleted_at IS NULL;

COMMIT;
