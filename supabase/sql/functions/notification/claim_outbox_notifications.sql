-- Function: claim_outbox_notifications
-- Description: Atomically claims pending notifications from outbox for processing
-- Used by: send-push-notifications edge function
-- Schema: internal
--
-- This function is the delivery layer for the new notification system.
-- It uses FOR UPDATE SKIP LOCKED to ensure safe concurrent processing.
--
-- Parameters:
--   batch_size: Maximum number of notifications to claim (default 50)
--
-- Behavior:
--   1. Resets stale claims (stuck > 15 minutes) - either back to pending or failed if max attempts reached
--   2. Claims pending notifications where due_at <= now() and attempts < 10
--   3. Returns claimed notifications for the edge function to deliver
--
-- Retry logic:
--   - Max 10 attempts per notification
--   - After 10 failed attempts, notification is permanently marked as 'failed'
--   - Stale claims (processing > 15 min) increment attempt counter

CREATE OR REPLACE FUNCTION internal.claim_outbox_notifications(batch_size INT DEFAULT 50)
RETURNS SETOF internal.notifications_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'internal', 'pg_temp'
AS $$
BEGIN
  -- Reset stale claims (stuck > 15 minutes) with bounded retries
  UPDATE notifications_outbox
  SET
    status = CASE
      WHEN attempts >= 10 THEN 'failed'  -- Max 10 attempts, then permanent failure
      ELSE 'pending'
    END,
    claimed_at = NULL,
    attempts = attempts + 1,
    error_message = CASE
      WHEN attempts >= 10 THEN 'Max retry attempts exceeded'
      ELSE error_message
    END
  WHERE status = 'sending'
    AND claimed_at < now() - INTERVAL '15 minutes';

  -- Claim and return batch (only pending with < 10 attempts)
  RETURN QUERY
  UPDATE notifications_outbox
  SET status = 'sending', claimed_at = now()
  WHERE id IN (
    SELECT id FROM notifications_outbox
    WHERE status = 'pending'
      AND due_at <= now()
      AND attempts < 10
    ORDER BY due_at
    LIMIT batch_size
    FOR UPDATE SKIP LOCKED
  )
  RETURNING *;
END;
$$;

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION internal.claim_outbox_notifications TO service_role;
