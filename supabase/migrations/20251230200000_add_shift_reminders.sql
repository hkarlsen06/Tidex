-- Migration: Add shift reminder preferences and tracking table
-- Adds columns to notification_preferences and creates shift_reminders_sent table

-- Add reminder preferences with DEFAULT true and 300 (5 hours)
-- This ensures new users get reminders enabled by default
ALTER TABLE notification_preferences
  ADD COLUMN shift_reminders_enabled BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN shift_reminder_minutes INTEGER NOT NULL DEFAULT 300
    CHECK (shift_reminder_minutes IN (60, 120, 300, 1440));

COMMENT ON COLUMN notification_preferences.shift_reminders_enabled IS 'Whether to receive reminder notifications before shifts start';
COMMENT ON COLUMN notification_preferences.shift_reminder_minutes IS 'How many minutes before shift to send reminder (60=1hr, 120=2hr, 300=5hr, 1440=24hr)';

-- Track sent reminders to prevent duplicates
-- Uses shift_instance_key (TEXT) instead of shift_id (UUID) to support recurring instances
CREATE TABLE shift_reminders_sent (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Format: "{type}:{id}:{date}:{start_time}" e.g. "single:abc-123:2025-01-15:08:00"
  -- This supports both single shifts and recurring shift instances
  shift_instance_key TEXT NOT NULL,

  -- Store reminder_minutes for future-proofing: if we later allow multiple reminder presets
  -- per shift (e.g., 24hr AND 1hr reminders), this avoids a migration
  reminder_minutes INTEGER NOT NULL,

  sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Prevent duplicate reminders for same shift instance AND reminder time
  -- This constraint acts as a distributed lock for claim-before-send
  -- Including reminder_minutes allows future support for multiple reminders per shift
  UNIQUE(user_id, shift_instance_key, reminder_minutes),

  -- Validate reminder_minutes matches allowed values
  CONSTRAINT shift_reminders_sent_reminder_minutes_check
    CHECK (reminder_minutes IN (60, 120, 300, 1440))
);

-- Index for efficient lookup and cleanup
CREATE INDEX idx_shift_reminders_sent_user
  ON shift_reminders_sent(user_id);

CREATE INDEX idx_shift_reminders_sent_cleanup
  ON shift_reminders_sent(sent_at);

-- RLS: Service role only (no client access needed)
-- Edge Function uses service role, no client queries this table
ALTER TABLE shift_reminders_sent ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role only"
  ON shift_reminders_sent FOR ALL
  USING (auth.role() = 'service_role');

COMMENT ON TABLE shift_reminders_sent IS 'Tracks sent shift reminders to prevent duplicate notifications';
COMMENT ON COLUMN shift_reminders_sent.shift_instance_key IS 'Unique key for shift instance: {type}:{id}:{date}:{start_time}';
COMMENT ON COLUMN shift_reminders_sent.reminder_minutes IS 'The reminder timing that was used (supports multiple reminders per shift in future)';

-- Backfill: Insert preference rows for users who have push_devices registered
-- but no notification_preferences row yet. This ensures existing users get reminders.
INSERT INTO notification_preferences (user_id, shift_reminders_enabled, shift_reminder_minutes)
SELECT DISTINCT pd.user_id, true, 300
FROM push_devices pd
LEFT JOIN notification_preferences np ON np.user_id = pd.user_id
WHERE np.user_id IS NULL
ON CONFLICT (user_id) DO NOTHING;

-- For users who already have a notification_preferences row, the new columns
-- will use their DEFAULT values (true, 300), so no explicit backfill needed.
