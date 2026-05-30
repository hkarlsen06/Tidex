ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS calendar_content_color_style text NOT NULL DEFAULT 'workplace';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'user_settings_calendar_content_color_style_valid'
      AND conrelid = 'public.user_settings'::regclass
  ) THEN
    ALTER TABLE public.user_settings
      ADD CONSTRAINT user_settings_calendar_content_color_style_valid
      CHECK (calendar_content_color_style IN ('workplace', 'monochrome'));
  END IF;
END $$;

COMMENT ON COLUMN public.user_settings.calendar_content_color_style IS
  'Calendar content color preference: workplace uses job colors, monochrome uses neutral text colors.';
