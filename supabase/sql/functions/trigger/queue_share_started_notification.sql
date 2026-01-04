-- Function: queue_share_started_notification
-- Description: Trigger function that queues notifications when shift sharing starts
-- Used by: AFTER INSERT trigger on shift_shares

CREATE OR REPLACE FUNCTION public.queue_share_started_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  sharer_name TEXT;
  viewer_prefs RECORD;
BEGIN
  -- Get the sharer's display name
  SELECT COALESCE(raw_user_meta_data->>'full_name', email, 'Noen')
  INTO sharer_name
  FROM auth.users
  WHERE id = NEW.owner_id;

  -- Check viewer's notification preferences
  SELECT shared_shifts_enabled
  INTO viewer_prefs
  FROM notification_preferences
  WHERE user_id = NEW.viewer_id;

  -- Only queue notification if viewer has shared_shifts_enabled (default true if no prefs)
  IF COALESCE(viewer_prefs.shared_shifts_enabled, true) = false THEN
    RETURN NEW;
  END IF;

  -- Insert notification for the viewer
  INSERT INTO internal.notification_queue (
    type,
    recipient_id,
    sender_id,
    payload,
    idempotency_key
  )
  VALUES (
    'share_started',
    NEW.viewer_id,
    NEW.owner_id,
    jsonb_build_object(
      'owner_id', NEW.owner_id,
      'owner_name', sharer_name
    ),
    'share_started:' || NEW.owner_id || ':' || NEW.viewer_id
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$function$;
