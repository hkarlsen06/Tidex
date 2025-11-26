-- Add currency preference to user_settings
-- Stores the display symbol directly (e.g., "kr", "NOK", "$", "€")
-- Default is "kr" for backward compatibility with existing Norwegian users

ALTER TABLE user_settings
ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'kr';

COMMENT ON COLUMN user_settings.currency IS 'Currency display symbol (e.g., kr, NOK, $, €). Stored value is displayed directly.';
