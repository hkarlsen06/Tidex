-- First time each app install reached a pre-auth onboarding step. These rows cover people
-- who never create an account, which public.onboarding_funnel_steps can't see.
-- The install id is a random UUID used only for this table, so rows aren't linked to users.
-- Clients write only through public.record_onboarding_preauth_step.

CREATE TABLE IF NOT EXISTS internal.onboarding_preauth_steps (
  install_id uuid NOT NULL,
  step text NOT NULL,
  reached_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (install_id, step),
  CONSTRAINT onboarding_preauth_steps_step_format
    CHECK (step ~ '^[a-z][a-z0-9_]{0,63}$')
);

COMMENT ON TABLE internal.onboarding_preauth_steps IS
  'First time an app install reached each pre-auth onboarding step. reached_at is client-reported and capped at the insert time.';

CREATE INDEX IF NOT EXISTS onboarding_preauth_steps_recorded_at_idx
  ON internal.onboarding_preauth_steps (recorded_at);

ALTER TABLE internal.onboarding_preauth_steps ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.onboarding_preauth_steps FROM PUBLIC, anon, authenticated;

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

REVOKE ALL ON FUNCTION public.record_onboarding_preauth_step(uuid, text, timestamptz)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_onboarding_preauth_step(uuid, text, timestamptz)
  TO anon, authenticated, service_role;
