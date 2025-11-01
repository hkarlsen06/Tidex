-- Remove deprecated wage-related columns from user_settings
-- Wage data is now stored in wage_snapshots table

ALTER TABLE public.user_settings
  DROP COLUMN IF EXISTS use_preset,
  DROP COLUMN IF EXISTS current_wage_level,
  DROP COLUMN IF EXISTS custom_wage,
  DROP COLUMN IF EXISTS custom_supplements;
