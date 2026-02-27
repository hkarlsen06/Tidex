-- Function: sync_default_job_to_legacy_settings
-- Description:
--   Mirrors default-job payroll fields to legacy user_settings fields.

CREATE OR REPLACE FUNCTION public.sync_default_job_to_legacy_settings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  IF NEW.is_default = true THEN
    UPDATE public.user_settings
    SET payroll_day = NEW.payroll_day,
        half_tax_month = NEW.half_tax_month,
        monthly_goal = NEW.monthly_goal
    WHERE user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;
