-- Function: validate_payroll_adjustment_job_owner
-- Description:
--   Allows payroll adjustments without a job_id, and validates that explicit
--   job_id references belong to the same active job owner.

CREATE OR REPLACE FUNCTION public.validate_payroll_adjustment_job_owner()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.job_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.jobs j
    WHERE j.id = NEW.job_id
      AND j.user_id = NEW.user_id
      AND j.deleted_at IS NULL
      AND j.archived_at IS NULL
    FOR SHARE
  ) THEN
    RAISE EXCEPTION 'job_id must belong to same user';
  END IF;

  RETURN NEW;
END;
$function$;
