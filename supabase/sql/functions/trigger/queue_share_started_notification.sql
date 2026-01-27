-- Function: queue_share_started_notification
-- Description: Trigger function that queues notifications when shift sharing starts
-- Used by: AFTER INSERT trigger on shift_shares
--
-- Writes to notifications_outbox (the working path) with localized messages
-- based on the viewer's locale preference.

CREATE OR REPLACE FUNCTION public.queue_share_started_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_sharer_name TEXT;
  v_viewer_locale TEXT;
  v_title TEXT;
  v_body TEXT;
  v_viewer_prefs RECORD;
BEGIN
  -- Check viewer's notification preferences first (before doing more work)
  SELECT shared_shifts_enabled
  INTO v_viewer_prefs
  FROM notification_preferences
  WHERE user_id = NEW.viewer_id;

  -- Skip if viewer has shared_shifts_enabled = false
  IF COALESCE(v_viewer_prefs.shared_shifts_enabled, true) = false THEN
    RETURN NEW;
  END IF;

  -- Get the sharer's display name
  SELECT COALESCE(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', email, 'Someone')
  INTO v_sharer_name
  FROM auth.users
  WHERE id = NEW.owner_id;

  IF v_sharer_name IS NULL THEN
    v_sharer_name := 'Someone';
  END IF;

  -- Get viewer's locale preference
  SELECT COALESCE(raw_user_meta_data->>'locale', 'en')
  INTO v_viewer_locale
  FROM auth.users
  WHERE id = NEW.viewer_id;

  -- Build localized message
  IF v_viewer_locale IN ('no', 'nb', 'nn') THEN
    v_title := v_sharer_name || ' deler vakter med deg';
    v_body := 'Trykk for å se ' || v_sharer_name || ' sine vakter';
  ELSE
    v_title := v_sharer_name || ' is sharing shifts with you';
    v_body := 'Tap to see ' || v_sharer_name || '''s shifts';
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
  )
  VALUES (
    NEW.owner_id,
    NEW.viewer_id,
    'share_started',
    now(),
    v_title,
    v_body,
    jsonb_build_object(
      'type', 'share_started',
      'owner_id', NEW.owner_id,
      'owner_name', v_sharer_name
    ),
    'share_started:' || NEW.owner_id || ':' || NEW.viewer_id
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$function$;
