-- Function: queue_recurring_shift_created_notification
-- Description: Trigger function that queues notifications when recurring shifts are created
-- Used by: AFTER INSERT trigger on recurring_shifts
--
-- Note: Recurring shift notifications always go to instant queue (never summary)
-- because they represent multiple future shifts. Muted users are still skipped.

CREATE OR REPLACE FUNCTION public.queue_recurring_shift_created_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  owner_name TEXT;
BEGIN
  -- Get the shift owner's display name from user_metadata (full_name only)
  SELECT
    COALESCE(
      raw_user_meta_data->>'full_name',
      raw_user_meta_data->>'name',
      email,
      'Noen'
    )
  INTO owner_name
  FROM auth.users
  WHERE id = NEW.user_id;

  IF owner_name IS NULL THEN
    owner_name := 'Noen';
  END IF;

  -- Recurring shifts always go to instant queue (not summary)
  -- Skip muted users
  -- Note: ss.blocked controls visibility, NOT notifications
  -- notification_frequency controls whether user gets notified (instant/summary/muted)
  INSERT INTO notification_queue (
    type,
    recipient_id,
    sender_id,
    payload,
    idempotency_key
  )
  SELECT
    'recurring_shift_created',
    ss.viewer_id,
    NEW.user_id,
    jsonb_build_object(
      'recurring_id', NEW.id,
      'owner_id', NEW.user_id,
      'owner_name', owner_name
    ),
    'recurring_created:' || NEW.id || ':' || ss.viewer_id
  FROM shift_shares ss
  LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
  WHERE ss.owner_id = NEW.user_id
    AND COALESCE(np.shared_shifts_enabled, true) = true
    AND COALESCE(ss.notification_frequency, 'instant') != 'muted'
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$function$;
