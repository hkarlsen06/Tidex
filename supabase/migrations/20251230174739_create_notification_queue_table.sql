-- Migration: Create notification_queue table for push notification delivery
-- This table queues notifications for async processing by Edge Functions

CREATE TABLE notification_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Notification type for routing/handling
  type TEXT NOT NULL CHECK (type IN (
    'shared_shift_created',
    'shared_shift_updated',
    'shared_shift_deleted',
    'share_request'  -- Future: when someone wants to share with you
  )),

  -- Who should receive this notification
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Who triggered the notification
  sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,

  -- Notification content (minimal - client fetches details)
  payload JSONB NOT NULL DEFAULT '{}',

  -- Delivery tracking with atomic claiming support
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending',     -- Waiting to be processed
    'processing',  -- Claimed by a worker
    'sent',        -- Successfully delivered
    'failed',      -- Delivery failed
    'skipped'      -- No devices registered
  )),
  error_message TEXT,
  retry_count INTEGER NOT NULL DEFAULT 0,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  claimed_at TIMESTAMPTZ,  -- When a worker claimed this row
  processed_at TIMESTAMPTZ,

  -- Prevent duplicate notifications for same event
  idempotency_key TEXT UNIQUE
);

-- Index for processing pending notifications with atomic claiming
CREATE INDEX idx_notification_queue_pending
  ON notification_queue(created_at)
  WHERE status = 'pending';

-- Index for finding stale "processing" rows (worker died)
CREATE INDEX idx_notification_queue_stale_processing
  ON notification_queue(claimed_at)
  WHERE status = 'processing';

CREATE INDEX idx_notification_queue_recipient ON notification_queue(recipient_id);

-- RLS: Only service role can access (Edge Functions bypass RLS automatically)
ALTER TABLE notification_queue ENABLE ROW LEVEL SECURITY;

-- No client policies - service role only (service role bypasses RLS)

COMMENT ON TABLE notification_queue IS 'Queue for push notifications processed by Edge Functions';
COMMENT ON COLUMN notification_queue.status IS 'pending=waiting, processing=claimed by worker, sent=delivered, failed=error, skipped=no devices';
COMMENT ON COLUMN notification_queue.claimed_at IS 'Timestamp when a worker claimed this row for processing';
COMMENT ON COLUMN notification_queue.idempotency_key IS 'Unique key to prevent duplicate notifications for the same event';
