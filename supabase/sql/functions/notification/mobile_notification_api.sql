-- Functions used by the native iOS app after the Next.js shutdown.

CREATE OR REPLACE FUNCTION public.register_push_device(
  p_platform text,
  p_apns_token text DEFAULT NULL,
  p_fcm_token text DEFAULT NULL,
  p_device_id text DEFAULT NULL,
  p_device_model text DEFAULT NULL,
  p_app_version text DEFAULT NULL
)
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

GRANT EXECUTE ON FUNCTION public.register_push_device(text, text, text, text, text, text) TO authenticated;

-- The legacy register_push_device(p_user_id uuid, p_fcm_token text, ...) overload was
-- dropped in 20260930170000_security_audit_hardening.sql. It let a caller who knew
-- another user's fcm_token take over that row.

CREATE OR REPLACE FUNCTION public.unregister_push_device(p_fcm_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  DELETE FROM internal.push_devices
  WHERE fcm_token = p_fcm_token
    AND user_id = v_user_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.unregister_push_device(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.unregister_push_device(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.unregister_push_device(text) TO authenticated;

-- Removes the caller's own push device row for an APNs (or FCM) token.
-- The iOS app calls this before sign-out so the device stops receiving the
-- previous user's notifications.
CREATE OR REPLACE FUNCTION public.unregister_my_push_device(p_device_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  IF NULLIF(p_device_token, '') IS NULL THEN
    RETURN;
  END IF;

  DELETE FROM internal.push_devices
  WHERE user_id = v_user_id
    AND (apns_token = p_device_token OR fcm_token = p_device_token);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.unregister_my_push_device(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.unregister_my_push_device(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.unregister_my_push_device(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_push_device_last_seen(p_fcm_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  UPDATE internal.push_devices
  SET last_seen_at = now()
  WHERE fcm_token = p_fcm_token
    AND user_id = v_user_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.update_push_device_last_seen(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.update_push_device_last_seen(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_push_device_last_seen(text) TO authenticated;
