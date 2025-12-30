-- Migration: Create function for atomic notification claiming
-- This prevents double-processing when Edge Functions run concurrently

CREATE OR REPLACE FUNCTION claim_pending_notifications(batch_size INTEGER DEFAULT 50)
RETURNS SETOF notification_queue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- First, reset any stale "processing" rows (worker died)
  -- Rows claimed more than 5 minutes ago are considered stale
  UPDATE notification_queue
  SET status = 'pending', claimed_at = NULL
  WHERE status = 'processing'
    AND claimed_at < NOW() - INTERVAL '5 minutes';

  -- Atomically claim and return rows
  -- FOR UPDATE SKIP LOCKED ensures no two workers claim the same row
  RETURN QUERY
  WITH claimed AS (
    UPDATE notification_queue
    SET
      status = 'processing',
      claimed_at = NOW()
    WHERE id IN (
      SELECT id
      FROM notification_queue
      WHERE status = 'pending'
      ORDER BY created_at
      FOR UPDATE SKIP LOCKED
      LIMIT batch_size
    )
    RETURNING *
  )
  SELECT * FROM claimed;
END;
$$;

COMMENT ON FUNCTION claim_pending_notifications IS 'Atomically claims pending notifications for processing. Returns claimed rows. Stale processing rows (>5min) are reset to pending.';
