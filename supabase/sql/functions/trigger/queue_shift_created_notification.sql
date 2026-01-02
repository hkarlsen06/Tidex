-- Function: queue_shift_created_notification
-- Description: Trigger function that queues notifications when shifts are created
-- Used by: AFTER INSERT trigger on user_shifts
--
-- Notification routing based on notification_frequency:
-- - 'instant': Queue to notification_queue for immediate delivery
-- - 'summary': Queue to pending_summary_notifications for daily digest
-- - 'muted': Skip notification entirely

CREATE OR REPLACE FUNCTION public.queue_shift_created_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  owner_name TEXT;
  likely_replacement BOOLEAN := false;
  is_recurring_conversion BOOLEAN := false;
BEGIN
  -- Check if this shift likely replaces a recently deleted one
  -- Match on same date only - if user deletes and creates on same day, it's an update
  SELECT EXISTS (
    SELECT 1
    FROM pending_shift_deletes
    WHERE owner_id = NEW.user_id
      AND shift_date = NEW.shift_date
      AND status = 'pending'
      AND check_at > now()
  ) INTO likely_replacement;

  -- If this is a likely replacement, skip the created notification
  -- The cron job will send "updated" instead after the window expires
  IF likely_replacement THEN
    RETURN NEW;
  END IF;

  -- Check if this shift is a recurring conversion (date is in exclusions of a recurring shift)
  -- This happens when user "edits" a recurring virtual shift - it creates a standalone shift
  SELECT EXISTS (
    SELECT 1
    FROM recurring_shifts
    WHERE user_id = NEW.user_id
      AND exclusions IS NOT NULL
      AND exclusions @> to_jsonb(NEW.shift_date::text)
  ) INTO is_recurring_conversion;

  -- Get the shift owner's display name from user_metadata
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

  -- Route to instant notification queue (for 'instant' frequency)
  -- Note: ss.blocked controls visibility ONLY (hides from /sharing list), NOT notifications
  -- notification_frequency controls whether user gets notified (instant/summary/muted)
  -- Blocked users still receive notifications - they just don't see the sharer in their list
  INSERT INTO notification_queue (
    type,
    recipient_id,
    sender_id,
    payload,
    idempotency_key
  )
  SELECT
    CASE WHEN is_recurring_conversion THEN 'shared_shift_updated' ELSE 'shared_shift_created' END,
    ss.viewer_id,
    NEW.user_id,
    jsonb_build_object(
      'shift_id', NEW.id,
      'shift_date', NEW.shift_date,
      'start_time', NEW.start_time,
      'end_time', NEW.end_time,
      'owner_id', NEW.user_id,
      'owner_name', owner_name
    ),
    CASE WHEN is_recurring_conversion
      THEN 'shift_recurring_converted:' || NEW.id || ':' || ss.viewer_id
      ELSE 'shift_created:' || NEW.id || ':' || ss.viewer_id
    END
  FROM shift_shares ss
  LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
  WHERE ss.owner_id = NEW.user_id
    AND COALESCE(np.shared_shifts_enabled, true) = true
    AND COALESCE(ss.notification_frequency, 'instant') = 'instant'
  ON CONFLICT (idempotency_key) DO NOTHING;

  -- Route to summary queue (for 'summary' frequency)
  INSERT INTO pending_summary_notifications (
    recipient_id,
    sender_id,
    shift_id,
    shift_date,
    start_time,
    end_time,
    owner_name,
    notification_type
  )
  SELECT
    ss.viewer_id,
    NEW.user_id,
    NEW.id,
    NEW.shift_date,
    NEW.start_time::time,
    NEW.end_time::time,
    owner_name,
    CASE WHEN is_recurring_conversion THEN 'updated' ELSE 'created' END
  FROM shift_shares ss
  LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
  WHERE ss.owner_id = NEW.user_id
    AND COALESCE(np.shared_shifts_enabled, true) = true
    AND ss.notification_frequency = 'summary'
  ON CONFLICT (recipient_id, sender_id, shift_id) DO NOTHING;

  -- Note: 'muted' frequency is handled by the WHERE clause exclusion

  RETURN NEW;
END;
$function$;
