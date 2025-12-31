-- Function: claim_pending_notifications
-- Description: Atomically claims pending notifications for processing with stale claim recovery
-- Used by: send-push-notifications edge function

CREATE OR REPLACE FUNCTION public.claim_pending_notifications(batch_size integer DEFAULT 50)
 RETURNS SETOF notification_queue
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$;
