BEGIN;

CREATE TABLE IF NOT EXISTS public.web_app_banner_dismissals (
  banner_key text NOT NULL CHECK (char_length(banner_key) <= 100),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  dismissed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (banner_key, user_id)
);

CREATE INDEX IF NOT EXISTS idx_web_app_banner_dismissals_dismissed_at
  ON public.web_app_banner_dismissals (dismissed_at DESC);

COMMENT ON TABLE public.web_app_banner_dismissals IS
  'Tracks per-user dismissals of important web app banners so unique web usage can be measured.';

COMMENT ON COLUMN public.web_app_banner_dismissals.banner_key IS
  'Stable identifier for the banner copy/campaign.';

ALTER TABLE public.web_app_banner_dismissals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own web app banner dismissals" ON public.web_app_banner_dismissals;
CREATE POLICY "Users can view own web app banner dismissals"
ON public.web_app_banner_dismissals
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own web app banner dismissals" ON public.web_app_banner_dismissals;
CREATE POLICY "Users can insert own web app banner dismissals"
ON public.web_app_banner_dismissals
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own web app banner dismissals" ON public.web_app_banner_dismissals;
CREATE POLICY "Users can update own web app banner dismissals"
ON public.web_app_banner_dismissals
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

COMMIT;
