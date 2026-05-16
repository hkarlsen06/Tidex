ALTER TABLE public.user_settings
  DROP COLUMN IF EXISTS direct_time_input,
  DROP COLUMN IF EXISTS full_minute_range;
