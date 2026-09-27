-- record_auth_diagnostic_event: anonymous callers could attach any user_id to
-- a diagnostic row. The claimed id now goes to metadata.reported_user_id and
-- user_id stays NULL, as in the repo source. The per-install rate limit reads
-- occurred_at so it can use auth_diagnostic_events_install_time_idx.
--
-- Also purge diagnostic rows older than 90 days every week.

CREATE OR REPLACE FUNCTION public.record_auth_diagnostic_event(p_event_type text, p_severity text DEFAULT 'info'::text, p_user_id uuid DEFAULT NULL::uuid, p_app_state text DEFAULT NULL::text, p_auth_event text DEFAULT NULL::text, p_app_version text DEFAULT NULL::text, p_build_number text DEFAULT NULL::text, p_os_version text DEFAULT NULL::text, p_device_model text DEFAULT NULL::text, p_locale text DEFAULT NULL::text, p_error_kind text DEFAULT NULL::text, p_error_message text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'auth'
AS $function$
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
    -- after the SDK has already lost the local session.
    v_install_id := NULLIF(left(COALESCE(v_metadata ->> 'install_id', ''), 80), '');
    IF v_install_id IS NULL THEN
      RAISE EXCEPTION 'Anonymous diagnostics require an install id';
    END IF;

    IF (
      SELECT COUNT(*)
      FROM internal.auth_diagnostic_events
      WHERE metadata ->> 'install_id' = v_install_id
        AND occurred_at >= now() - interval '1 hour'
    ) >= 120 THEN
      RAISE EXCEPTION 'Diagnostic rate limit exceeded';
    END IF;

    -- The caller can claim any user id here, so keep it in metadata as
    -- diagnostic context instead of user_id.
    IF p_user_id IS NOT NULL THEN
      v_metadata := v_metadata || jsonb_build_object('reported_user_id', p_user_id);
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
$function$;

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'purge-auth-diagnostic-events';

SELECT cron.schedule(
  'purge-auth-diagnostic-events',
  '45 4 * * 0',
  $cron$DELETE FROM internal.auth_diagnostic_events WHERE occurred_at < now() - interval '90 days';$cron$
);
