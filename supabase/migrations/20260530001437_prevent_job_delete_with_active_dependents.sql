-- Prevent deleting jobs that still own active history rows.
-- Jobs with history should be archived instead so shifts keep their workplace
-- context and payroll calculations do not fall back to unrelated wage data.

CREATE SCHEMA IF NOT EXISTS internal;

CREATE OR REPLACE FUNCTION internal.prevent_job_delete_with_active_dependents()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.user_shifts us
    WHERE us.job_id = NEW.id
      AND us.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'cannot delete job with active shifts'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.recurring_shifts rs
    WHERE rs.job_id = NEW.id
      AND rs.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'cannot delete job with active recurring shifts'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.payroll_adjustments pa
    WHERE pa.job_id = NEW.id
      AND pa.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'cannot delete job with active payroll adjustments'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION internal.prevent_job_delete_with_active_dependents()
  FROM public;
REVOKE EXECUTE ON FUNCTION internal.prevent_job_delete_with_active_dependents()
  FROM anon;
REVOKE EXECUTE ON FUNCTION internal.prevent_job_delete_with_active_dependents()
  FROM authenticated;

DROP TRIGGER IF EXISTS prevent_job_delete_with_active_dependents ON public.jobs;
CREATE TRIGGER prevent_job_delete_with_active_dependents
  BEFORE UPDATE OF deleted_at ON public.jobs
  FOR EACH ROW
  WHEN (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL)
  EXECUTE FUNCTION internal.prevent_job_delete_with_active_dependents();
