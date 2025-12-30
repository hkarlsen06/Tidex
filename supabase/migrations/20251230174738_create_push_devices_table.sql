-- Migration: Create push_devices table for storing FCM tokens
-- This table stores device registration tokens for push notifications

CREATE TABLE push_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),

  -- Device identification for account switching
  device_id TEXT, -- iOS: identifierForVendor, allows token rotation
  device_model TEXT, -- e.g., "iPhone 14 Pro"
  app_version TEXT,  -- e.g., "1.2.0"

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Token is globally unique; when same device switches users, update user_id
  UNIQUE(fcm_token)
);

-- Index for looking up user's devices
CREATE INDEX idx_push_devices_user_id ON push_devices(user_id);

-- Index for device lookup (token rotation scenarios)
CREATE INDEX idx_push_devices_device_id ON push_devices(device_id) WHERE device_id IS NOT NULL;

-- Auto-update updated_at on row update
CREATE OR REPLACE FUNCTION update_push_devices_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER push_devices_updated_at
  BEFORE UPDATE ON push_devices
  FOR EACH ROW
  EXECUTE FUNCTION update_push_devices_updated_at();

-- RLS: Users can only manage their own devices
ALTER TABLE push_devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own devices"
  ON push_devices FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own devices"
  ON push_devices FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own devices"
  ON push_devices FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own devices"
  ON push_devices FOR DELETE
  USING (auth.uid() = user_id);

-- Note: Service role bypasses RLS automatically, no policy needed

COMMENT ON TABLE push_devices IS 'Stores FCM tokens for push notifications. Each device registers its token here.';
COMMENT ON COLUMN push_devices.fcm_token IS 'Firebase Cloud Messaging token for this device';
COMMENT ON COLUMN push_devices.device_id IS 'Stable device identifier (iOS identifierForVendor) for handling token rotation';
COMMENT ON COLUMN push_devices.last_seen_at IS 'Last time this device was active, used for cleanup of stale tokens';
