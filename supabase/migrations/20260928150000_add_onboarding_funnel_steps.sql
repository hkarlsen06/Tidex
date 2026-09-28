-- First time each user reached an onboarding step, for funnel analysis.
-- The iOS app inserts rows with ON CONFLICT DO NOTHING, so the first timestamp wins.
-- Clients can insert and read only their own rows. PostgREST's ON CONFLICT (user_id, step)
-- needs SELECT on the conflict columns, which is why clients also get SELECT.

CREATE TABLE IF NOT EXISTS public.onboarding_funnel_steps (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  step text NOT NULL,
  reached_at timestamptz NOT NULL DEFAULT now(),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, step),
  CONSTRAINT onboarding_funnel_steps_step_format
    CHECK (step ~ '^[a-z][A-Za-z0-9_]{0,63}$')
);

COMMENT ON TABLE public.onboarding_funnel_steps IS
  'First time a user reached each onboarding step. reached_at is client-reported; pre-auth steps are buffered on the device and sent after sign-in.';

ALTER TABLE public.onboarding_funnel_steps ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.onboarding_funnel_steps FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.onboarding_funnel_steps TO authenticated;
GRANT ALL ON TABLE public.onboarding_funnel_steps TO service_role;

DROP POLICY IF EXISTS onboarding_funnel_steps_insert_own ON public.onboarding_funnel_steps;
CREATE POLICY onboarding_funnel_steps_insert_own
  ON public.onboarding_funnel_steps
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS onboarding_funnel_steps_select_own ON public.onboarding_funnel_steps;
CREATE POLICY onboarding_funnel_steps_select_own
  ON public.onboarding_funnel_steps
  FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));
