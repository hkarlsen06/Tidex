-- Create Apple IAP notification tables for idempotency and orphan handling

-- Apple notifications idempotency ledger
CREATE TABLE IF NOT EXISTS apple_notifications (
  id text PRIMARY KEY,
  notification_type text NOT NULL,
  subtype text,
  original_transaction_id text,
  transaction_id text,
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  raw_payload jsonb
);

COMMENT ON TABLE apple_notifications IS 'Idempotency ledger for Apple App Store Server Notifications';

CREATE INDEX IF NOT EXISTS idx_apple_notifications_original_transaction_id ON apple_notifications(original_transaction_id);
CREATE INDEX IF NOT EXISTS idx_apple_notifications_received_at ON apple_notifications(received_at);

-- Apple orphan notifications (notifications that couldn't be matched to a user)
CREATE TABLE IF NOT EXISTS apple_orphan_notifications (
  id text PRIMARY KEY,
  notification_type text NOT NULL,
  subtype text,
  original_transaction_id text,
  app_account_token uuid,
  received_at timestamptz NOT NULL DEFAULT now(),
  raw_payload jsonb NOT NULL,
  reconciled_at timestamptz,
  reconciled_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

COMMENT ON TABLE apple_orphan_notifications IS 'Apple notifications that could not be matched to a user';

CREATE INDEX IF NOT EXISTS idx_apple_orphan_notifications_original_transaction_id ON apple_orphan_notifications(original_transaction_id);
CREATE INDEX IF NOT EXISTS idx_apple_orphan_notifications_app_account_token ON apple_orphan_notifications(app_account_token);
CREATE INDEX IF NOT EXISTS idx_apple_orphan_notifications_received_at ON apple_orphan_notifications(received_at);

-- Enable RLS on both tables
ALTER TABLE apple_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE apple_orphan_notifications ENABLE ROW LEVEL SECURITY;
