CREATE OR REPLACE FUNCTION internal.queue_auth_diagnostic_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'internal', 'public', 'auth', 'pg_temp'
AS $$
DECLARE
  v_recipient_id uuid := '032d8c2a-9af6-4777-99f0-24e2c4058bf3'::uuid;
  v_subject_user text := COALESCE(NEW.user_id::text, 'unknown user');
  v_body text;
BEGIN
  IF NEW.severity NOT IN ('warning', 'error') OR NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_body := NEW.severity || ' · ' || v_subject_user;

  IF NEW.app_version IS NOT NULL THEN
    v_body := v_body || ' · v' || NEW.app_version;
  END IF;

  IF NEW.error_message IS NOT NULL THEN
    v_body := v_body || ' · ' || left(NEW.error_message, 120);
  END IF;

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
  VALUES (
    NEW.user_id,
    v_recipient_id,
    'auth_diagnostic_event',
    'Tidex auth diagnostic: ' || NEW.event_type,
    v_body,
    jsonb_build_object(
      'type', 'auth_diagnostic_event',
      'diagnostic_event_id', NEW.id,
      'diagnostic_user_id', NEW.user_id,
      'event_type', NEW.event_type,
      'severity', NEW.severity,
      'app_state', NEW.app_state,
      'auth_event', NEW.auth_event,
      'app_version', NEW.app_version,
      'build_number', NEW.build_number,
      'os_version', NEW.os_version,
      'device_model', NEW.device_model,
      'occurred_at', NEW.occurred_at,
      'deeplink', 'tidex://admin?tab=diagnostics&eventId=' || NEW.id::text
    ),
    'auth_diagnostic_event:' || NEW.id::text || ':' || v_recipient_id::text,
    now(),
    'pending'
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$$;
