-- Function: prevent_job_delete_with_active_dependents
-- Description:
--   Prevents soft-deleting jobs that still have active shifts, recurring
--   shifts, or payroll adjustments. Historical rows should keep their job
--   context; use archiving instead.

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
