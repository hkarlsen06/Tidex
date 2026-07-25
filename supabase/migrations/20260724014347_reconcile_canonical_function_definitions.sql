-- Reapply canonical source definitions where the linked catalog drifted from
-- the latest committed migration or source file.

-- Source: supabase/sql/functions/auth/record_auth_diagnostic_event.sql
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
) IS 'Records bounded auth lifecycle diagnostics from anonymous or authenticated clients.';

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
) FROM PUBLIC;

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

-- Source: supabase/sql/functions/messaging/edit_message.sql
CREATE OR REPLACE FUNCTION public.edit_message(
  p_message_id uuid,
  p_body text
)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb,
  reactions jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_sender_user_id uuid;
  v_message_type text;
  v_deleted_at timestamptz;
  v_existing_body text;
  v_normalized_body text;
  v_did_update boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT
    m.thread_id,
    m.sender_user_id,
    m.message_type,
    m.deleted_at,
    NULLIF(regexp_replace(COALESCE(m.body, ''), '^\s+|\s+$', '', 'g'), '')
  INTO
    v_thread_id,
    v_sender_user_id,
    v_message_type,
    v_deleted_at,
    v_existing_body
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_thread_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  IF NOT public.can_access_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF v_sender_user_id <> v_uid THEN
    RAISE EXCEPTION 'Only the sender can edit this message';
  END IF;

  IF v_message_type <> 'user' THEN
    RAISE EXCEPTION 'Only user messages can be edited';
  END IF;

  IF v_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Deleted messages cannot be edited';
  END IF;

  IF v_existing_body IS NULL THEN
    RAISE EXCEPTION 'Only text messages can be edited';
  END IF;

  v_normalized_body := NULLIF(
    regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'),
    ''
  );

  IF v_normalized_body IS NULL THEN
    RAISE EXCEPTION 'Message body cannot be empty';
  END IF;

  IF char_length(v_normalized_body) > 5000 THEN
    RAISE EXCEPTION 'Message body exceeds the 5000 character limit';
  END IF;

  IF public.is_objectionable_text(v_normalized_body) THEN
    RAISE EXCEPTION 'Message blocked by safety filter';
  END IF;

  IF v_normalized_body IS DISTINCT FROM v_existing_body THEN
    UPDATE public.messages
    SET
      body = v_normalized_body,
      edited_at = now()
    WHERE messages.id = p_message_id;

    v_did_update := FOUND;
  END IF;

  IF v_did_update THEN
    PERFORM internal.append_thread_event(
      v_thread_id,
      'message_upserted',
      'message',
      p_message_id,
      internal.build_message_sync_payload_v2(p_message_id),
      v_uid
    );

    PERFORM internal.emit_thread_upserted_inbox_event_v2(tm.user_id, v_thread_id)
    FROM public.thread_memberships tm
    WHERE tm.thread_id = v_thread_id
      AND tm.status = 'active'
      AND internal.can_access_thread_as_user(v_thread_id, tm.user_id);
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.get_message_payload(p_message_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.edit_message(uuid, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.edit_message(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.edit_message(uuid, text) TO authenticated;

-- Source: supabase/sql/functions/admin/admin_log_action.sql
CREATE OR REPLACE FUNCTION public.admin_log_action(
  p_admin_id uuid,
  p_admin_email text,
  p_action text,
  p_target_id uuid DEFAULT NULL,
  p_target_email text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $$
DECLARE
  v_log_id uuid;
BEGIN
  -- Validate action is in allowed list
  IF p_action NOT IN (
    'user_lookup', 'user_ban', 'user_unban',
    'grant_admin', 'revoke_admin',
    'grant_grandfathered', 'revoke_grandfathered',
    'create_trial_subscription', 'revoke_trial_subscription',
    'broadcast_sent', 'user_list_viewed', 'admin_action_failed',
    'sql_executed',
    'shift_share_created', 'shift_share_updated', 'shift_share_deleted'
  ) THEN
    RAISE EXCEPTION 'Invalid action type: %', p_action;
  END IF;

  INSERT INTO internal.admin_audit_log (
    admin_id,
    admin_email,
    action,
    target_user_id,
    target_email,
    metadata
  ) VALUES (
    p_admin_id,
    p_admin_email,
    p_action,
    p_target_id,
    p_target_email,
    p_metadata
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_log_action(
  uuid,
  text,
  text,
  uuid,
  text,
  jsonb
) FROM public;
REVOKE EXECUTE ON FUNCTION public.admin_log_action(
  uuid,
  text,
  text,
  uuid,
  text,
  jsonb
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_log_action(
  uuid,
  text,
  text,
  uuid,
  text,
  jsonb
) TO service_role;

COMMENT ON FUNCTION public.admin_log_action(
  uuid,
  text,
  text,
  uuid,
  text,
  jsonb
) IS 'Logs admin actions to audit log. SECURITY DEFINER - only callable via service role.';
