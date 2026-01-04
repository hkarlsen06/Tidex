-- Function: queue_feedback_responded_notification
-- Description: Trigger function that queues a notification for the user when an admin responds to their feedback
-- Used by: AFTER UPDATE trigger on feedback table
-- Note: Only triggers on FIRST response (not edits to existing responses)

CREATE OR REPLACE FUNCTION public.queue_feedback_responded_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth', 'pg_temp'
AS $$
BEGIN
  -- Only trigger when response is FIRST added (not on edits)
  IF OLD.response IS NULL AND NEW.response IS NOT NULL THEN
    INSERT INTO internal.notification_queue (
      type,
      recipient_id,
      sender_id,
      payload,
      idempotency_key
    ) VALUES (
      'feedback_responded',
      NEW.user_id,
      NEW.responded_by,
      jsonb_build_object(
        'feedback_id', NEW.id,
        'response_preview', LEFT(NEW.response, 150)
      ),
      'feedback_responded:' || NEW.id  -- Stable key, one notification per feedback
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- Triggers on feedback table:
-- 1. a_on_feedback_responded_notify (AFTER UPDATE FOR EACH ROW) - queues notification for user
-- 2. z_on_feedback_updated_send_notifications (AFTER UPDATE FOR EACH STATEMENT) - fires push
