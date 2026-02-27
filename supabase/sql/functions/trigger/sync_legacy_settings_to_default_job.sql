-- Function: sync_legacy_settings_to_default_job
-- Description:
--   Mirrors legacy payroll fields from user_settings to default job.

CREATE OR REPLACE FUNCTION public.sync_legacy_settings_to_default_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_id uuid;
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  v_job_id := public.ensure_default_job(NEW.user_id);

  UPDATE public.jobs
  SET payroll_day = NEW.payroll_day,
      half_tax_month = NEW.half_tax_month,
      monthly_goal = NEW.monthly_goal
  WHERE id = v_job_id;

  RETURN NEW;
END;
$$;
