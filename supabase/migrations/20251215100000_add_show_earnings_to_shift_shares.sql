-- Add show_earnings column to shift_shares table
-- Allows users to control whether recipients can see earnings data or only hours
-- Default: true (backward compatible - existing shares continue showing earnings)

ALTER TABLE public.shift_shares
ADD COLUMN show_earnings BOOLEAN NOT NULL DEFAULT true;

-- Add comment for documentation
COMMENT ON COLUMN public.shift_shares.show_earnings IS 'When false, viewers can only see hours data, not earnings/wages';
