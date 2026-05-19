CREATE TABLE IF NOT EXISTS internal.auth_diagnostic_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  event_type text NOT NULL,
  severity text NOT NULL DEFAULT 'info',
  app_state text,
  auth_event text,
  app_version text,
  build_number text,
  os_version text,
  device_model text,
  locale text,
  error_kind text,
  error_message text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT auth_diagnostic_events_event_type_check CHECK (
    event_type IN (
      'app_launch',
      'initial_session_received',
      'initial_session_missing',
      'initial_session_check_failed',
      'initial_session_timeout',
      'auth_state_changed',
      'authenticated',
      'signed_out_received',
      'user_initiated_sign_out',
      'session_fetch_failed',
      'token_refresh_started',
      'token_refresh_succeeded',
      'token_refresh_failed',
      'foreground_session_failed',
      'revoked_session_detected',
      'recoverable_auth_failure',
      'forced_unauthenticated'
    )
  ),
  CONSTRAINT auth_diagnostic_events_severity_check CHECK (
    severity IN ('debug', 'info', 'warning', 'error')
  ),
  CONSTRAINT auth_diagnostic_events_metadata_object_check CHECK (
    jsonb_typeof(metadata) = 'object'
  ),
  CONSTRAINT auth_diagnostic_events_error_message_length_check CHECK (
    error_message IS NULL OR length(error_message) <= 500
  )
);

COMMENT ON TABLE internal.auth_diagnostic_events IS
  'Privacy-minimal client auth diagnostics for investigating unexpected logout/session failures.';
COMMENT ON COLUMN internal.auth_diagnostic_events.user_id IS
  'Authenticated user id when available. Anonymous reports may provide the app cached last-authenticated user id and must be treated as client-reported.';
COMMENT ON COLUMN internal.auth_diagnostic_events.metadata IS
  'Small sanitized event context. Must not contain access tokens, refresh tokens, passwords, email addresses, or phone numbers.';

CREATE INDEX IF NOT EXISTS auth_diagnostic_events_user_time_idx
  ON internal.auth_diagnostic_events (user_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS auth_diagnostic_events_type_time_idx
  ON internal.auth_diagnostic_events (event_type, occurred_at DESC);

CREATE INDEX IF NOT EXISTS auth_diagnostic_events_error_time_idx
  ON internal.auth_diagnostic_events (occurred_at DESC)
  WHERE severity IN ('warning', 'error');

CREATE INDEX IF NOT EXISTS auth_diagnostic_events_install_time_idx
  ON internal.auth_diagnostic_events ((metadata ->> 'install_id'), occurred_at DESC)
  WHERE metadata ? 'install_id';

ALTER TABLE internal.auth_diagnostic_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.auth_diagnostic_events FROM public;
REVOKE ALL ON TABLE internal.auth_diagnostic_events FROM anon;
REVOKE ALL ON TABLE internal.auth_diagnostic_events FROM authenticated;

CREATE OR REPLACE FUNCTION public.record_auth_diagnostic_event(
  p_event_type text,
  p_severity text DEFAULT 'info',
  p_user_id uuid DEFAULT NULL,
  p_app_state text DEFAULT NULL,
  p_auth_event text DEFAULT NULL,
  p_app_version text DEFAULT NULL,
  p_build_number text DEFAULT NULL,
  p_os_version text DEFAULT NULL,
  p_device_model text DEFAULT NULL,
  p_locale text DEFAULT NULL,
  p_error_kind text DEFAULT NULL,
  p_error_message text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, internal, auth
AS $$
DECLARE
  v_auth_uid uuid := auth.uid();
  v_user_id uuid;
  v_metadata jsonb := COALESCE(p_metadata, '{}'::jsonb);
  v_install_id text;
BEGIN
  IF p_event_type IS NULL OR p_event_type NOT IN (
    'app_launch',
    'initial_session_received',
    'initial_session_missing',
    'initial_session_check_failed',
    'initial_session_timeout',
    'auth_state_changed',
    'authenticated',
    'signed_out_received',
    'user_initiated_sign_out',
    'session_fetch_failed',
    'token_refresh_started',
    'token_refresh_succeeded',
    'token_refresh_failed',
    'foreground_session_failed',
    'revoked_session_detected',
    'recoverable_auth_failure',
    'forced_unauthenticated'
  ) THEN
    RAISE EXCEPTION 'Invalid diagnostic event type';
  END IF;

  IF COALESCE(p_severity, 'info') NOT IN ('debug', 'info', 'warning', 'error') THEN
    RAISE EXCEPTION 'Invalid diagnostic severity';
  END IF;

  IF jsonb_typeof(v_metadata) <> 'object' THEN
    RAISE EXCEPTION 'Diagnostic metadata must be a JSON object';
  END IF;

  IF length(v_metadata::text) > 4096 THEN
    RAISE EXCEPTION 'Diagnostic metadata is too large';
  END IF;

  IF v_auth_uid IS NOT NULL THEN
    IF p_user_id IS NOT NULL AND p_user_id <> v_auth_uid THEN
      RAISE EXCEPTION 'Diagnostic user id does not match authenticated user';
    END IF;
    v_user_id := v_auth_uid;
  ELSE
    -- Anonymous reports are accepted so the app can record launch/session failures
    -- after the SDK has already lost the local session. Do not store client-supplied
    -- user ids in the relational column; anonymous identity is non-authoritative
    -- diagnostic context only.
    v_install_id := NULLIF(left(COALESCE(v_metadata ->> 'install_id', ''), 80), '');
    IF v_install_id IS NULL THEN
      RAISE EXCEPTION 'Anonymous diagnostics require an install id';
    END IF;

    IF (
      SELECT COUNT(*)
      FROM internal.auth_diagnostic_events
      WHERE metadata ->> 'install_id' = v_install_id
        AND created_at >= now() - interval '1 hour'
    ) >= 120 THEN
      RAISE EXCEPTION 'Diagnostic rate limit exceeded';
    END IF;

    v_user_id := NULL;
  END IF;

  INSERT INTO internal.auth_diagnostic_events (
    user_id,
    event_type,
    severity,
    app_state,
    auth_event,
    app_version,
    build_number,
    os_version,
    device_model,
    locale,
    error_kind,
    error_message,
    metadata
  )
  VALUES (
    v_user_id,
    p_event_type,
    COALESCE(p_severity, 'info'),
    NULLIF(left(COALESCE(p_app_state, ''), 80), ''),
    NULLIF(left(COALESCE(p_auth_event, ''), 80), ''),
    NULLIF(left(COALESCE(p_app_version, ''), 40), ''),
    NULLIF(left(COALESCE(p_build_number, ''), 40), ''),
    NULLIF(left(COALESCE(p_os_version, ''), 80), ''),
    NULLIF(left(COALESCE(p_device_model, ''), 80), ''),
    NULLIF(left(COALESCE(p_locale, ''), 40), ''),
    NULLIF(left(COALESCE(p_error_kind, ''), 120), ''),
    NULLIF(left(COALESCE(p_error_message, ''), 500), ''),
    v_metadata
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

COMMENT ON FUNCTION public.record_auth_diagnostic_event(
  text,
  text,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb
) IS
  'Records sanitized iOS auth/session diagnostics. Callable by anon for logged-out launch failures; authenticated calls are pinned to auth.uid().';

REVOKE ALL ON FUNCTION public.record_auth_diagnostic_event(
  text,
  text,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb
) FROM public;
GRANT EXECUTE ON FUNCTION public.record_auth_diagnostic_event(
  text,
  text,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb
) TO anon, authenticated;

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
  -- Keep developer notifications actionable. Debug/info events remain queryable
  -- in internal.auth_diagnostic_events without sending a visible push.
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

DROP TRIGGER IF EXISTS on_auth_diagnostic_event_notify ON internal.auth_diagnostic_events;
CREATE TRIGGER on_auth_diagnostic_event_notify
  AFTER INSERT ON internal.auth_diagnostic_events
  FOR EACH ROW
  EXECUTE FUNCTION internal.queue_auth_diagnostic_notification();

REVOKE ALL ON FUNCTION internal.queue_auth_diagnostic_notification() FROM public;
REVOKE ALL ON FUNCTION internal.queue_auth_diagnostic_notification() FROM anon;
REVOKE ALL ON FUNCTION internal.queue_auth_diagnostic_notification() FROM authenticated;
GRANT EXECUTE ON FUNCTION internal.queue_auth_diagnostic_notification() TO service_role;
