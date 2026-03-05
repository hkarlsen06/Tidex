-- Function: ensure_default_job
-- Description:
--   Ensures a user has one active default job and returns its ID.
--   Used by compatibility triggers for legacy clients that omit job_id.

CREATE OR REPLACE FUNCTION public.ensure_default_job(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_id uuid;
  v_payroll_day integer;
  v_half_tax_month integer;
  v_monthly_goal integer;
  v_currency text;
BEGIN
  SELECT j.id
  INTO v_job_id
  FROM public.jobs j
  WHERE j.user_id = p_user_id
    AND j.is_default = true
    AND j.deleted_at IS NULL
    AND j.archived_at IS NULL
  LIMIT 1;

  IF v_job_id IS NULL THEN
    SELECT
      COALESCE(us.payroll_day, 15),
      us.half_tax_month,
      COALESCE(us.monthly_goal, 20000),
      COALESCE(us.currency, 'kr')
    INTO v_payroll_day, v_half_tax_month, v_monthly_goal, v_currency
    FROM public.user_settings us
    WHERE us.user_id = p_user_id
    LIMIT 1;

    INSERT INTO public.jobs (
      user_id,
      name,
      is_default,
      payroll_day,
      half_tax_month,
      monthly_goal,
      currency
    )
    VALUES (
      p_user_id,
      'Jobb',
      true,
      COALESCE(v_payroll_day, 15),
      v_half_tax_month,
      COALESCE(v_monthly_goal, 20000),
      COALESCE(v_currency, 'kr')
    )
    ON CONFLICT DO NOTHING;

    SELECT j.id
    INTO v_job_id
    FROM public.jobs j
    WHERE j.user_id = p_user_id
      AND j.is_default = true
      AND j.deleted_at IS NULL
      AND j.archived_at IS NULL
    LIMIT 1;
  END IF;

  RETURN v_job_id;
END;
$$;
