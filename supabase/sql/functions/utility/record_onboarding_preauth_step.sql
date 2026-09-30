CREATE OR REPLACE FUNCTION public.record_onboarding_preauth_step(
  p_install_id uuid,
  p_step text,
  p_reached_at timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = internal, pg_temp
AS $$
BEGIN
  IF p_install_id IS NULL OR p_step IS NULL OR p_step !~ '^[a-z][a-z0-9_]{0,63}$' THEN
    RAISE EXCEPTION 'Invalid onboarding step';
  END IF;

  -- Anyone with the anon key can call this with made-up install ids, so cap the
  -- total write rate. Real traffic is a few hundred rows a month. The error makes
  -- the app keep the step and retry it with the next pre-auth page.
  IF (
    SELECT count(*)
    FROM internal.onboarding_preauth_steps
    WHERE recorded_at >= now() - interval '1 hour'
  ) >= 1000 THEN
    RAISE EXCEPTION 'Onboarding step rate limit exceeded';
  END IF;

  INSERT INTO internal.onboarding_preauth_steps (install_id, step, reached_at)
  VALUES (
    p_install_id,
    p_step,
    LEAST(COALESCE(p_reached_at, now()), now())
  )
  ON CONFLICT (install_id, step) DO NOTHING;
END;
$$;
