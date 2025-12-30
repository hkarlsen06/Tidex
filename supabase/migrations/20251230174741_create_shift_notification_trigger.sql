-- Migration: Create trigger to queue notifications when shifts are created
-- This trigger queues notifications for all users who the shift owner shares with

-- Function to queue notifications when a shift is created
-- Uses single INSERT...SELECT instead of loop for performance
-- Note: We only store minimal data (IDs). The client/Edge Function fetches user details.
CREATE OR REPLACE FUNCTION queue_shift_created_notification()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Single INSERT...SELECT instead of loop for better performance
  -- We queue notifications for all viewers who:
  -- 1. The shift owner shares with (ss.owner_id = NEW.user_id)
  -- 2. Haven't blocked the owner (ss.blocked = false)
  -- 3. Have notifications enabled (or haven't set preferences yet, default true)
  INSERT INTO notification_queue (
    type,
    recipient_id,
    sender_id,
    payload,
    idempotency_key
  )
  SELECT
    'shared_shift_created',
    ss.viewer_id,
    NEW.user_id,
    jsonb_build_object(
      'shift_id', NEW.id,
      'shift_date', NEW.shift_date,
      'owner_id', NEW.user_id
      -- Note: Minimal payload. Edge Function/client fetches user name on delivery.
    ),
    'shift_created:' || NEW.id || ':' || ss.viewer_id
  FROM shift_shares ss
  LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
  WHERE ss.owner_id = NEW.user_id
    AND ss.blocked = false
    AND COALESCE(np.shared_shifts_enabled, true) = true
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on shift insert
CREATE TRIGGER on_shift_created_notify
  AFTER INSERT ON shifts
  FOR EACH ROW
  EXECUTE FUNCTION queue_shift_created_notification();

COMMENT ON FUNCTION queue_shift_created_notification IS 'Queues push notifications for all users who receive shared shifts from the shift creator';
