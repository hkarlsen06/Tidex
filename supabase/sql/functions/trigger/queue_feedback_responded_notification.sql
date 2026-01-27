-- Function: queue_feedback_responded_notification
-- Description: Trigger function that queues a notification for the user when an admin responds to their feedback
-- Used by: AFTER UPDATE trigger on feedback table
-- Note: Only triggers on FIRST response (not edits to existing responses)
--
-- Writes to notifications_outbox (the working path) with localized messages
-- based on the user's locale preference.

CREATE OR REPLACE FUNCTION public.queue_feedback_responded_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth', 'pg_temp'
AS $$
DECLARE
  v_user_locale TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  -- Only trigger when response is FIRST added (not on edits)
  IF OLD.response IS NULL AND NEW.response IS NOT NULL THEN
    -- Get user's locale preference
    SELECT COALESCE(raw_user_meta_data->>'locale', 'en')
    INTO v_user_locale
    FROM auth.users
    WHERE id = NEW.user_id;

    -- Build localized message
    IF v_user_locale IN ('no', 'nb', 'nn') THEN
      v_title := 'Svar på tilbakemeldingen din';
      v_body := LEFT(NEW.response, 150);
    ELSE
      v_title := 'Response to your feedback';
      v_body := LEFT(NEW.response, 150);
    END IF;

    -- Insert notification to outbox (the working path)
    INSERT INTO internal.notifications_outbox (
      owner_id,
      recipient_id,
      notification_type,
      due_at,
      title,
      body,
      data_payload,
      idempotency_key
    ) VALUES (
      NEW.responded_by,
      NEW.user_id,
      'feedback_responded',
      now(),
      v_title,
      v_body,
      jsonb_build_object(
        'type', 'feedback_responded',
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
