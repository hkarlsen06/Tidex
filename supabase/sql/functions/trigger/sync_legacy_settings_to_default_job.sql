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
  v_default_currency text;
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

  SELECT COALESCE(j.currency, 'kr')
  INTO v_default_currency
  FROM public.jobs j
  WHERE j.id = v_job_id
  LIMIT 1;

  IF NEW.currency IS DISTINCT FROM v_default_currency THEN
    UPDATE public.user_settings
    SET currency = v_default_currency
    WHERE user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;
