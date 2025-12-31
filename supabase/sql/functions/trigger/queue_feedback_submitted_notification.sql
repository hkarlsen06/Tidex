-- Function: queue_feedback_submitted_notification
-- Description: Trigger function that queues notifications for all admins when a user submits feedback
-- Used by: AFTER INSERT trigger on feedback table

CREATE OR REPLACE FUNCTION public.queue_feedback_submitted_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'auth'
AS $$
DECLARE
  v_user_name text;
BEGIN
  -- Get the submitter's name
  SELECT COALESCE(raw_user_meta_data->>'full_name', NEW.user_email)
  INTO v_user_name
  FROM auth.users
  WHERE id = NEW.user_id;

  -- Set-based insert for all admins (no loop)
  INSERT INTO notification_queue (
    type,
    recipient_id,
    sender_id,
    payload,
    idempotency_key
  )
  SELECT
    'feedback_submitted',
    u.id,
    NEW.user_id,
    jsonb_build_object(
      'feedback_id', NEW.id,
      'user_name', v_user_name,
      'user_email', NEW.user_email,
      'message_preview', LEFT(NEW.message, 100)
    ),
    'feedback_submitted:' || NEW.id || ':' || u.id
  FROM auth.users u
  WHERE (u.raw_app_meta_data->>'role') = 'admin'
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Triggers on feedback table:
-- 1. a_on_feedback_submitted_notify (AFTER INSERT FOR EACH ROW) - queues notifications for admins
-- 2. z_on_feedback_inserted_send_notifications (AFTER INSERT FOR EACH STATEMENT) - fires push
