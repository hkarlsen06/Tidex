-- Add half_tax_month column to user_settings
-- Allows users to configure which month (11=November, 12=December) to apply half tax deduction
-- NULL means the feature is disabled

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS half_tax_month INTEGER CHECK (half_tax_month IN (11, 12) OR half_tax_month IS NULL);

COMMENT ON COLUMN public.user_settings.half_tax_month IS 'Month number (11 or 12) for half tax deduction, or NULL to disable';
