-- Function: assign_job_id_and_validate_owner
-- Description:
--   Trigger helper for user_shifts/recurring_shifts/wage_snapshots.
--   Fills missing job_id with default job and validates ownership.

CREATE OR REPLACE FUNCTION public.assign_job_id_and_validate_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.job_id IS NULL THEN
    NEW.job_id := public.ensure_default_job(NEW.user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.jobs j
    WHERE j.id = NEW.job_id
      AND j.user_id = NEW.user_id
      AND j.deleted_at IS NULL
      AND j.archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'job_id must belong to same user';
  END IF;

  RETURN NEW;
END;
$$;
