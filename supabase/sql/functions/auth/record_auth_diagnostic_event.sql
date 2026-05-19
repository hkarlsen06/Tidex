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
