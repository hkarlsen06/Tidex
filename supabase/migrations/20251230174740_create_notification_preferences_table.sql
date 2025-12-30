-- Migration: Create notification_preferences table for user notification settings
-- This table stores per-user notification preferences

CREATE TABLE notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Notification type toggles
  shared_shifts_enabled BOOLEAN NOT NULL DEFAULT true,

  -- Future notification types (commented out for now)
  -- weekly_summary_enabled BOOLEAN NOT NULL DEFAULT false,
  -- shift_reminders_enabled BOOLEAN NOT NULL DEFAULT false,

  -- Quiet hours (optional, for future use)
  quiet_hours_start TIME,  -- e.g., '22:00'
  quiet_hours_end TIME,    -- e.g., '07:00'

  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_notification_preferences_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notification_preferences_updated_at
  BEFORE UPDATE ON notification_preferences
  FOR EACH ROW
  EXECUTE FUNCTION update_notification_preferences_updated_at();

-- RLS: Users can only manage their own preferences
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own preferences"
  ON notification_preferences FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own preferences"
  ON notification_preferences FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own preferences"
  ON notification_preferences FOR UPDATE
  USING (auth.uid() = user_id);

COMMENT ON TABLE notification_preferences IS 'Per-user notification preferences';
COMMENT ON COLUMN notification_preferences.shared_shifts_enabled IS 'Whether to receive notifications when someone shares a new shift';
COMMENT ON COLUMN notification_preferences.quiet_hours_start IS 'Start of quiet hours (notifications suppressed)';
COMMENT ON COLUMN notification_preferences.quiet_hours_end IS 'End of quiet hours';
