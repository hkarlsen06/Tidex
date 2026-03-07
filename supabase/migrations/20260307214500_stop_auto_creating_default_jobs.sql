-- Stop creating default jobs for users who have not started work setup.
-- Keep lazy default-job creation for legacy work writes that omit job_id.

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.profiles (id)
  VALUES (NEW.id)
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$function$;

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

  SELECT j.id
  INTO v_job_id
  FROM public.jobs j
  WHERE j.user_id = NEW.user_id
    AND j.is_default = true
    AND j.deleted_at IS NULL
    AND j.archived_at IS NULL
  LIMIT 1;

  IF v_job_id IS NULL THEN
    RETURN NEW;
  END IF;

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
