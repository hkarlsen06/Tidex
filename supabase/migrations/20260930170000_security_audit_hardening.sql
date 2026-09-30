-- Security audit hardening (2026-09-30).
--
-- 1. Revoke anon/authenticated table, sequence and function grants in the
--    `internal` and `supabase_functions` schemas.
-- 2. register_push_device: drop the unsafe legacy overload and scope the
--    fcm_token lookup to the caller.
-- 3. Lock admin_* leftovers to authenticated (or drop them).
-- 4. Global hourly cap for anonymous auth diagnostics.
-- 5. Block account deletion during an impersonation session.
-- 6. Drop storage policies for the nonexistent `avatars` bucket.
-- 7. Pre-account-takeover mitigation trigger on auth.identities.
-- 8. Sharing email lookup only matches proven addresses.

-- 1. internal / supabase_functions grants ---------------------------------
-- anon and authenticated have no USAGE on `internal`, so this is defense in
-- depth against a later `GRANT USAGE`. No pg_default_acl entry exists for
-- `internal`, so new objects there get no anon/authenticated grants.
REVOKE ALL ON ALL TABLES IN SCHEMA internal FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA internal FROM anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA internal FROM anon, authenticated;

-- postgres is a member of supabase_functions_admin (the owner), so these
-- REVOKEs run as the owner.
REVOKE ALL ON ALL TABLES IN SCHEMA supabase_functions FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA supabase_functions FROM anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA supabase_functions FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA supabase_functions
  REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA supabase_functions
  REVOKE ALL ON SEQUENCES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA supabase_functions
  REVOKE ALL ON FUNCTIONS FROM anon, authenticated;

-- 2. register_push_device -------------------------------------------------
-- The legacy (uuid, text, ...) overload is unused by iOS, and its
-- ON CONFLICT (fcm_token) DO UPDATE SET user_id = EXCLUDED.user_id let a caller
-- who knew another user's token take over that row.
DROP FUNCTION IF EXISTS public.register_push_device(uuid, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.register_push_device(p_platform text, p_apns_token text DEFAULT NULL::text, p_fcm_token text DEFAULT NULL::text, p_device_id text DEFAULT NULL::text, p_device_model text DEFAULT NULL::text, p_app_version text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_existing_id uuid;
  v_insert_fcm text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_platform IS NULL OR p_platform NOT IN ('ios', 'android', 'web') THEN
    RAISE EXCEPTION 'Invalid platform. Must be ios, android, or web';
  END IF;

  IF COALESCE(NULLIF(p_apns_token, ''), NULLIF(p_fcm_token, '')) IS NULL THEN
    RAISE EXCEPTION 'Either apnsToken or fcmToken is required';
  END IF;

  IF p_apns_token IS NOT NULL THEN
    DELETE FROM internal.push_devices
    WHERE apns_token = p_apns_token
      AND user_id <> v_user_id;
  END IF;

  IF p_device_id IS NOT NULL THEN
    SELECT id
    INTO v_existing_id
    FROM internal.push_devices
    WHERE user_id = v_user_id
      AND device_id = p_device_id
    ORDER BY updated_at DESC
    LIMIT 1;
  END IF;

  -- Only reuse the caller's own row. If another user's row holds this fcm_token,
  -- the insert below hits the unique constraint and returns 'already_registered'
  -- without touching that row.
  IF v_existing_id IS NULL AND p_fcm_token IS NOT NULL THEN
    SELECT id
    INTO v_existing_id
    FROM internal.push_devices
    WHERE fcm_token = p_fcm_token
      AND user_id = v_user_id
    LIMIT 1;
  END IF;

  IF v_existing_id IS NULL AND p_apns_token IS NOT NULL AND p_fcm_token IS NULL THEN
    SELECT id
    INTO v_existing_id
    FROM internal.push_devices
    WHERE user_id = v_user_id
      AND platform = p_platform
    ORDER BY updated_at DESC
    LIMIT 1;
  END IF;

  IF v_existing_id IS NOT NULL THEN
    UPDATE internal.push_devices
    SET
      device_id = p_device_id,
      device_model = p_device_model,
      app_version = p_app_version,
      last_seen_at = v_now,
      updated_at = v_now,
      apns_environment = CASE
        WHEN p_apns_token IS NOT NULL AND p_apns_token IS DISTINCT FROM apns_token THEN NULL
        ELSE apns_environment
      END,
      apns_token = COALESCE(p_apns_token, apns_token),
      fcm_token = COALESCE(p_fcm_token, fcm_token)
    WHERE id = v_existing_id;

    IF p_device_id IS NOT NULL THEN
      DELETE FROM internal.push_devices
      WHERE user_id = v_user_id
        AND device_id = p_device_id
        AND id <> v_existing_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'action', 'updated');
  END IF;

  v_insert_fcm := p_fcm_token;
  IF p_apns_token IS NOT NULL AND v_insert_fcm IS NULL THEN
    v_insert_fcm := 'apns_' || left(p_apns_token, 32);
  END IF;

  BEGIN
    INSERT INTO internal.push_devices (
      user_id,
      platform,
      apns_token,
      fcm_token,
      device_id,
      device_model,
      app_version,
      last_seen_at,
      updated_at
    ) VALUES (
      v_user_id,
      p_platform,
      p_apns_token,
      v_insert_fcm,
      p_device_id,
      p_device_model,
      p_app_version,
      v_now,
      v_now
    );
  EXCEPTION
    WHEN unique_violation THEN
      RETURN jsonb_build_object('success', true, 'action', 'already_registered');
  END;

  RETURN jsonb_build_object('success', true, 'action', 'inserted');
END;
$function$;

-- 3. admin_* leftovers ----------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.admin_delete_message_api(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_get_report_messages_api(uuid, integer) FROM PUBLIC, anon;
-- Unused SECURITY INVOKER duplicate of admin_get_audit_log_api. It reads
-- internal.admin_audit_log, which only service_role can reach.
DROP FUNCTION IF EXISTS public.admin_get_audit_log(integer, text, uuid);
-- public.admin_get_subscribers no longer exists.

-- 4. record_auth_diagnostic_event global anonymous cap --------------------
CREATE INDEX IF NOT EXISTS auth_diagnostic_events_anon_time_idx
  ON internal.auth_diagnostic_events (occurred_at DESC)
  WHERE user_id IS NULL;

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

    -- Callers can invent install ids, so the per-install cap above does not bound
    -- writes. Also cap all anonymous rows per hour. The observed peak is 272 an
    -- hour, so 3000 leaves room for a real auth outage.
    IF (
      SELECT COUNT(*)
      FROM internal.auth_diagnostic_events
      WHERE user_id IS NULL
        AND occurred_at >= now() - interval '1 hour'
    ) >= 3000 THEN
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

-- 5. prepare_user_for_deletion --------------------------------------------
CREATE OR REPLACE FUNCTION public.prepare_user_for_deletion(target_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
BEGIN
  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'target_user_id cannot be null';
  END IF;

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF auth.uid() != target_user_id THEN
    RAISE EXCEPTION 'You can only delete your own account';
  END IF;

  -- An admin impersonating a user must not be able to delete that user's account.
  IF public.is_impersonation_session() THEN
    RAISE EXCEPTION 'Accounts cannot be deleted during an impersonation session'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.abuse_reports
  SET reviewed_by = NULL
  WHERE reviewed_by = target_user_id;

  DELETE FROM public.abuse_reports
  WHERE reporter_user_id = target_user_id
     OR reported_user_id = target_user_id;

  DELETE FROM public.threads t
  USING public.direct_threads dt
  WHERE t.id = dt.thread_id
    AND (
      dt.user_low_id = target_user_id
      OR dt.user_high_id = target_user_id
    );

  DELETE FROM public.thread_user_state WHERE user_id = target_user_id;
  DELETE FROM public.thread_memberships WHERE user_id = target_user_id;
  DELETE FROM public.messages WHERE sender_user_id = target_user_id;

  DELETE FROM internal.impersonation_rate_limits WHERE admin_user_id = target_user_id;
  DELETE FROM internal.app_account_tokens WHERE user_id = target_user_id;
  DELETE FROM internal.push_devices WHERE user_id = target_user_id;
  DELETE FROM internal.notifications_outbox WHERE owner_id = target_user_id OR recipient_id = target_user_id;

  INSERT INTO internal.admin_audit_log (
    admin_id,
    action,
    target_user_id,
    admin_email,
    target_email,
    metadata
  )
  SELECT
    target_user_id,
    'user_deleted_self',
    target_user_id,
    COALESCE(u.email, u.phone, 'unknown'),
    COALESCE(u.email, u.phone, 'unknown'),
    jsonb_build_object('deletion_type', 'self_service', 'deleted_at', now())
  FROM auth.users u
  WHERE u.id = target_user_id;
END;
$function$;

-- 6. storage policies for the nonexistent `avatars` bucket -----------------
DROP POLICY IF EXISTS "avatars: insert own" ON storage.objects;
DROP POLICY IF EXISTS "avatars: update own" ON storage.objects;
DROP POLICY IF EXISTS "delete own avatar" ON storage.objects;
DROP POLICY IF EXISTS "read own avatar" ON storage.objects;
DROP POLICY IF EXISTS "update own avatar" ON storage.objects;
DROP POLICY IF EXISTS "upload own avatar" ON storage.objects;

-- 7. pre-account-takeover mitigation --------------------------------------
-- Function: internal.strip_unverified_email_login_on_oauth_link
-- Description: Pre-account-takeover mitigation. Runs after GoTrue inserts a
--              google or apple identity. If the same user still has an email
--              identity whose address was never verified, that email+password
--              login may belong to someone who signed up with an address they
--              do not own (MAILER_AUTOCONFIRM=true skips verification). The
--              function then clears the password, deletes the unverified email
--              identity and deletes the user's existing sessions.
--              This mirrors GoTrue's RemoveUnconfirmedIdentities
--              (internal/models/user.go), which does not run when autoconfirm
--              marks the user as confirmed. GoTrue stores "no password" as NULL.
--              GoTrue creates the session for the sign-in in progress after it
--              inserts the identity, so that session survives.
-- Trade-off: an unverified-email user who links Google or Apple by hand from
--            settings also loses the password and is signed out.
-- Used by: AFTER INSERT trigger on auth.identities.
-- Security: SECURITY DEFINER (owner postgres can modify auth.users,
--           auth.identities and auth.sessions). EXECUTE is revoked from
--           public, anon and authenticated. The trigger fires as
--           supabase_auth_admin without needing EXECUTE.

CREATE OR REPLACE FUNCTION internal.strip_unverified_email_login_on_oauth_link()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_removed integer;
BEGIN
  DELETE FROM auth.identities
  WHERE user_id = NEW.user_id
    AND provider = 'email'
    AND id <> NEW.id
    AND COALESCE(identity_data ->> 'email_verified', '') <> 'true';

  GET DIAGNOSTICS v_removed = ROW_COUNT;

  IF v_removed > 0 THEN
    UPDATE auth.users
    SET encrypted_password = NULL
    WHERE id = NEW.user_id;

    -- Deleting a session cascades to auth.refresh_tokens and auth.mfa_amr_claims.
    DELETE FROM auth.sessions
    WHERE user_id = NEW.user_id;
  END IF;

  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION internal.strip_unverified_email_login_on_oauth_link() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_identity_oauth_linked ON auth.identities;
CREATE TRIGGER on_auth_identity_oauth_linked
AFTER INSERT ON auth.identities
FOR EACH ROW
WHEN (NEW.provider IN ('google', 'apple'))
EXECUTE FUNCTION internal.strip_unverified_email_login_on_oauth_link();

-- 8. sharing email lookup -------------------------------------------------
CREATE OR REPLACE FUNCTION public.find_user_by_email(search_email text)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  -- Match only a user who proved the address: a verified email identity, or a
  -- google/apple identity carrying that email. auth.identities.email is the
  -- generated, indexed lower(identity_data ->> 'email').
  SELECT i.user_id
  FROM auth.identities i
  WHERE i.email = lower(search_email)
    AND (
      (i.provider = 'email' AND i.identity_data ->> 'email_verified' = 'true')
      OR i.provider IN ('google', 'apple')
    )
  ORDER BY i.created_at NULLS LAST, i.id
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.manage_sharing_action(p_action text, p_identifier text DEFAULT NULL::text, p_recipient_id uuid DEFAULT NULL::uuid, p_show_earnings boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_target_id uuid;
  v_normalized text;
  v_identifier text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;



  IF p_action = 'createShare' THEN
    IF p_identifier IS NULL OR btrim(p_identifier) = '' THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Vennligst oppgi en gyldig e-post, telefonnummer eller brukernavn'
      );
    END IF;

    v_identifier := btrim(p_identifier);

    IF position('@' IN v_identifier) > 0 AND left(v_identifier, 1) <> '@' THEN
      -- Only match a user who proved ownership of the address.
      v_target_id := public.find_user_by_email(v_identifier);
    ELSE
      v_identifier := lower(v_identifier);
      IF left(v_identifier, 1) = '@' THEN
        v_identifier := substr(v_identifier, 2);
      END IF;

      SELECT id INTO v_target_id
      FROM public.profiles
      WHERE username = v_identifier
      LIMIT 1;

      IF v_target_id IS NULL THEN
        v_normalized := regexp_replace(p_identifier, '\D', '', 'g');
        IF length(v_normalized) = 8 THEN
          v_normalized := '47' || v_normalized;
        ELSIF left(v_normalized, 2) = '00' THEN
          v_normalized := substr(v_normalized, 3);
        END IF;

        SELECT id INTO v_target_id
        FROM auth.users
        WHERE phone = v_normalized
        LIMIT 1;
      END IF;
    END IF;
  ELSIF p_action = 'shareBack' THEN
    v_target_id := p_recipient_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Ugyldig handling');
  END IF;

  IF v_target_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Fant ingen bruker med denne e-posten, telefonnummeret eller brukernavnet'
    );
  END IF;

  IF v_target_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du kan ikke dele med deg selv');
  END IF;

  -- A block lives on the pair's shift_shares rows. Refuse a new share in
  -- either direction while one exists.
  IF EXISTS (
    SELECT 1
    FROM public.shift_shares
    WHERE (
      (owner_id = v_user_id AND viewer_id = v_target_id)
      OR (owner_id = v_target_id AND viewer_id = v_user_id)
    )
      AND blocked_by_user_id IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du kan ikke dele vaktene dine med denne brukeren');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.shift_shares
    WHERE owner_id = v_user_id
      AND viewer_id = v_target_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du deler allerede vaktene dine med denne brukeren');
  END IF;

  INSERT INTO public.shift_shares (
    owner_id,
    viewer_id,
    show_earnings,
    muted,
    owner_muted
  ) VALUES (
    v_user_id,
    v_target_id,
    COALESCE(p_show_earnings, false),
    false,
    false
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;
