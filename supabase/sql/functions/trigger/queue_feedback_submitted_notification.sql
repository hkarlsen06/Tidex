-- Function: queue_feedback_submitted_notification
-- Description: Trigger function that inserts notifications into notifications_outbox
--              for all admins when a user submits feedback
-- Used by: AFTER INSERT trigger on feedback table

CREATE OR REPLACE FUNCTION public.queue_feedback_submitted_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth', 'pg_temp'
AS $$
DECLARE
  v_user_name text;
  v_admin_id uuid;
BEGIN
  -- Get the submitter's name
  SELECT COALESCE(raw_user_meta_data->>'full_name', NEW.user_email)
  INTO v_user_name
  FROM auth.users
  WHERE id = NEW.user_id;

  -- Insert notification for each admin directly into notifications_outbox
  INSERT INTO internal.notifications_outbox (
    owner_id,
    recipient_id,
    notification_type,
    title,
    body,
    data_payload,
    idempotency_key,
    due_at,
    status
  )
  SELECT
    NEW.user_id,
    u.id,
    'feedback_submitted',
    'Ny tilbakemelding',
    v_user_name || ': ' || LEFT(NEW.message, 100) || CASE WHEN LENGTH(NEW.message) > 100 THEN '...' ELSE '' END,
    jsonb_build_object(
      'type', 'feedback_submitted',
      'feedback_id', NEW.id,
      'user_name', v_user_name,
      'user_email', NEW.user_email
    ),
    'feedback:' || NEW.id || ':' || u.id,
    NOW(),
    'pending'
  FROM auth.users u
  WHERE (u.raw_app_meta_data->>'role') = 'admin'
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Trigger on feedback table:
-- on_feedback_submitted_notify (AFTER INSERT FOR EACH ROW) - queues notifications for admins
