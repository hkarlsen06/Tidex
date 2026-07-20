-- ActivityKit Live Activity authenticated registration and service-role delivery RPCs.
-- Keep synchronized with the CLI migration that owns the backing table/columns.

CREATE OR REPLACE FUNCTION public.register_live_activity_device(
  p_device_id text,
  p_push_to_start_token text,
  p_time_zone text,
  p_app_version text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_push_device_id uuid;
  v_conflicting_user_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(p_device_id), '') IS NULL THEN
    RAISE EXCEPTION 'device id is required' USING ERRCODE = '22023';
  END IF;

  IF NULLIF(btrim(p_push_to_start_token), '') IS NULL
     OR p_push_to_start_token !~ '^[0-9A-Fa-f]{32,512}$' THEN
    RAISE EXCEPTION 'invalid live activity push-to-start token' USING ERRCODE = '22023';
  END IF;

  IF NULLIF(btrim(p_time_zone), '') IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_timezone_names
       WHERE name = p_time_zone
     ) THEN
    RAISE EXCEPTION 'invalid IANA time zone' USING ERRCODE = '22023';
  END IF;

  SELECT pd.id
  INTO v_push_device_id
  FROM internal.push_devices pd
  WHERE pd.user_id = v_user_id
    AND pd.device_id = p_device_id
  ORDER BY pd.updated_at DESC, pd.id
  LIMIT 1
  FOR UPDATE;

  IF v_push_device_id IS NULL THEN
    RAISE EXCEPTION 'push device must be registered before live activities'
      USING ERRCODE = '23503';
  END IF;

  SELECT pd.user_id
  INTO v_conflicting_user_id
  FROM internal.push_devices pd
  WHERE pd.live_activity_push_to_start_token = lower(p_push_to_start_token)
    AND pd.id <> v_push_device_id
  LIMIT 1;

  IF v_conflicting_user_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM internal.push_devices pd
      WHERE pd.live_activity_push_to_start_token = lower(p_push_to_start_token)
        AND pd.device_id = p_device_id
    ) THEN
      UPDATE internal.push_devices
      SET live_activity_push_to_start_token = NULL,
          updated_at = now()
      WHERE live_activity_push_to_start_token = lower(p_push_to_start_token)
        AND id <> v_push_device_id;
    ELSE
      RAISE EXCEPTION 'live activity token is registered to another device'
        USING ERRCODE = '23505';
    END IF;
  END IF;

  UPDATE internal.push_devices
  SET live_activity_push_to_start_token = lower(p_push_to_start_token),
      time_zone = p_time_zone,
      app_version = COALESCE(p_app_version, app_version),
      last_seen_at = now(),
      updated_at = now()
  WHERE id = v_push_device_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.register_live_activity_update_token(
  p_device_id text,
  p_shift_id text,
  p_activity_id text,
  p_push_token text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_push_device_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(p_device_id), '') IS NULL
     OR NULLIF(btrim(p_shift_id), '') IS NULL
     OR NULLIF(btrim(p_activity_id), '') IS NULL THEN
    RAISE EXCEPTION 'device id, shift id, and activity id are required'
      USING ERRCODE = '22023';
  END IF;

  IF NULLIF(btrim(p_push_token), '') IS NULL
     OR p_push_token !~ '^[0-9A-Fa-f]{32,512}$' THEN
    RAISE EXCEPTION 'invalid live activity update token' USING ERRCODE = '22023';
  END IF;

  SELECT pd.id
  INTO v_push_device_id
  FROM internal.push_devices pd
  WHERE pd.user_id = v_user_id
    AND pd.device_id = p_device_id
  ORDER BY pd.updated_at DESC, pd.id
  LIMIT 1
  FOR UPDATE;

  IF v_push_device_id IS NULL THEN
    RAISE EXCEPTION 'push device not found' USING ERRCODE = '23503';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM internal.live_activity_deliveries lad
    JOIN internal.push_devices pd ON pd.id = lad.push_device_id
    WHERE lad.update_token = lower(p_push_token)
      AND pd.user_id <> v_user_id
  ) THEN
    RAISE EXCEPTION 'live activity update token belongs to another user'
      USING ERRCODE = '23505';
  END IF;

  -- ActivityKit is authoritative for the current activity on this device.
  -- Retire stale server-side registrations before accepting a remote or local start.
  UPDATE internal.live_activity_deliveries
  SET status = 'failed',
      claimed_at = NULL,
      activity_id = NULL,
      update_token = NULL,
      last_error = 'Superseded by ActivityKit registration',
      updated_at = now()
  WHERE push_device_id = v_push_device_id
    AND shift_id <> p_shift_id
    AND status IN ('starting', 'active', 'ending');

  INSERT INTO internal.live_activity_deliveries (
    push_device_id,
    shift_id,
    status,
    activity_id,
    update_token,
    active_at,
    attempts,
    last_error,
    claimed_at,
    updated_at
  ) VALUES (
    v_push_device_id,
    p_shift_id,
    'active',
    p_activity_id,
    lower(p_push_token),
    now(),
    0,
    NULL,
    NULL,
    now()
  )
  ON CONFLICT (push_device_id, shift_id) DO UPDATE
  SET status = 'active',
      activity_id = EXCLUDED.activity_id,
      update_token = EXCLUDED.update_token,
      active_at = COALESCE(internal.live_activity_deliveries.active_at, now()),
      ended_at = NULL,
      end_sent_at = NULL,
      attempts = 0,
      last_error = NULL,
      claimed_at = NULL,
      updated_at = now();
END;
$function$;

CREATE OR REPLACE FUNCTION public.end_live_activity_registration(
  p_device_id text,
  p_activity_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;

  UPDATE internal.live_activity_deliveries lad
  SET status = 'ended',
      claimed_at = NULL,
      ended_at = COALESCE(lad.ended_at, now()),
      last_error = NULL,
      updated_at = now()
  FROM internal.push_devices pd
  WHERE pd.id = lad.push_device_id
    AND pd.user_id = v_user_id
    AND pd.device_id = p_device_id
    AND lad.activity_id = p_activity_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.unregister_live_activity_device(p_device_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_push_device_ids uuid[];
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;

  SELECT array_agg(pd.id)
  INTO v_push_device_ids
  FROM internal.push_devices pd
  WHERE pd.user_id = v_user_id
    AND pd.device_id = p_device_id;

  IF v_push_device_ids IS NULL THEN
    RETURN;
  END IF;

  UPDATE internal.live_activity_deliveries
  SET status = 'failed',
      claimed_at = NULL,
      update_token = NULL,
      last_error = 'Live Activity device unregistered',
      updated_at = now()
  WHERE push_device_id = ANY(v_push_device_ids)
    AND status IN ('starting', 'active', 'ending');

  UPDATE internal.push_devices
  SET live_activity_push_to_start_token = NULL,
      updated_at = now()
  WHERE id = ANY(v_push_device_ids);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.register_live_activity_device(text, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.register_live_activity_device(text, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.register_live_activity_device(text, text, text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.register_live_activity_update_token(text, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.register_live_activity_update_token(text, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.register_live_activity_update_token(text, text, text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.end_live_activity_registration(text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.end_live_activity_registration(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.end_live_activity_registration(text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.unregister_live_activity_device(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.unregister_live_activity_device(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.unregister_live_activity_device(text) TO authenticated;

CREATE OR REPLACE FUNCTION internal.claim_live_activity_start(
  p_push_device_id uuid,
  p_shift_id text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_delivery_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM internal.push_devices pd
    WHERE pd.id = p_push_device_id
      AND pd.live_activity_push_to_start_token IS NOT NULL
  ) THEN
    RETURN NULL;
  END IF;

  INSERT INTO internal.live_activity_deliveries (
    push_device_id,
    shift_id,
    status,
    claimed_at,
    attempts,
    updated_at
  ) VALUES (
    p_push_device_id,
    p_shift_id,
    'starting',
    now(),
    1,
    now()
  )
  ON CONFLICT (push_device_id, shift_id) DO UPDATE
  SET status = 'starting',
      claimed_at = now(),
      attempts = CASE
        WHEN internal.live_activity_deliveries.status = 'failed' THEN 1
        ELSE internal.live_activity_deliveries.attempts + 1
      END,
      last_error = NULL,
      updated_at = now()
  WHERE (
      internal.live_activity_deliveries.status = 'starting'
      AND internal.live_activity_deliveries.start_sent_at IS NULL
      AND internal.live_activity_deliveries.attempts < 10
      AND (
        internal.live_activity_deliveries.claimed_at IS NULL
        OR internal.live_activity_deliveries.claimed_at < now() - interval '15 minutes'
      )
    ) OR (
      internal.live_activity_deliveries.status = 'failed'
      AND EXISTS (
        SELECT 1
        FROM internal.push_devices pd
        WHERE pd.id = internal.live_activity_deliveries.push_device_id
          AND pd.live_activity_push_to_start_token IS NOT NULL
          AND pd.updated_at > internal.live_activity_deliveries.updated_at
      )
    )
  RETURNING id INTO v_delivery_id;

  RETURN v_delivery_id;
EXCEPTION
  WHEN unique_violation THEN
    -- Another nonterminal Live Activity already owns this physical device.
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.complete_live_activity_start(
  p_delivery_id uuid,
  p_apns_environment text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_push_device_id uuid;
BEGIN
  IF p_apns_environment NOT IN ('production', 'sandbox') THEN
    RAISE EXCEPTION 'invalid APNs environment' USING ERRCODE = '22023';
  END IF;

  UPDATE internal.live_activity_deliveries
  SET start_sent_at = COALESCE(start_sent_at, now()),
      claimed_at = NULL,
      last_error = NULL,
      updated_at = now()
  WHERE id = p_delivery_id
    AND status = 'starting'
    AND start_sent_at IS NULL
  RETURNING push_device_id INTO v_push_device_id;

  IF v_push_device_id IS NOT NULL THEN
    UPDATE internal.push_devices
    SET apns_environment = p_apns_environment,
        updated_at = now()
    WHERE id = v_push_device_id;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.fail_live_activity_start(
  p_delivery_id uuid,
  p_error text,
  p_invalidate_token boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_push_device_id uuid;
BEGIN
  UPDATE internal.live_activity_deliveries
  SET status = CASE
        WHEN p_invalidate_token OR attempts >= 10 THEN 'failed'
        ELSE 'starting'
      END,
      claimed_at = NULL,
      last_error = left(COALESCE(p_error, 'Unknown APNs start error'), 1000),
      updated_at = now()
  WHERE id = p_delivery_id
    AND status = 'starting'
    AND start_sent_at IS NULL
  RETURNING push_device_id INTO v_push_device_id;

  IF p_invalidate_token AND v_push_device_id IS NOT NULL THEN
    UPDATE internal.push_devices
    SET live_activity_push_to_start_token = NULL,
        updated_at = now()
    WHERE id = v_push_device_id;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.claim_live_activity_end(p_delivery_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_claimed boolean := false;
BEGIN
  UPDATE internal.live_activity_deliveries
  SET status = 'ending',
      claimed_at = now(),
      attempts = CASE WHEN status = 'active' THEN 1 ELSE attempts + 1 END,
      updated_at = now()
  WHERE id = p_delivery_id
    AND update_token IS NOT NULL
    AND end_sent_at IS NULL
    AND (
      status = 'active'
      OR (
        status = 'ending'
        AND attempts < 10
        AND (claimed_at IS NULL OR claimed_at < now() - interval '15 minutes')
      )
    );

  v_claimed := FOUND;
  RETURN v_claimed;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.complete_live_activity_end(p_delivery_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'internal', 'pg_temp'
AS $function$
BEGIN
  UPDATE internal.live_activity_deliveries
  SET status = 'ended',
      end_sent_at = COALESCE(end_sent_at, now()),
      ended_at = COALESCE(ended_at, now()),
      claimed_at = NULL,
      last_error = NULL,
      updated_at = now()
  WHERE id = p_delivery_id
    AND status = 'ending';
END;
$function$;

CREATE OR REPLACE FUNCTION internal.fail_live_activity_end(
  p_delivery_id uuid,
  p_error text,
  p_invalidate_token boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'internal', 'pg_temp'
AS $function$
BEGIN
  UPDATE internal.live_activity_deliveries
  SET status = CASE
        WHEN p_invalidate_token OR attempts >= 10 THEN 'failed'
        ELSE 'ending'
      END,
      update_token = CASE WHEN p_invalidate_token THEN NULL ELSE update_token END,
      claimed_at = NULL,
      last_error = left(COALESCE(p_error, 'Unknown APNs end error'), 1000),
      updated_at = now()
  WHERE id = p_delivery_id
    AND status = 'ending'
    AND end_sent_at IS NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION internal.claim_live_activity_start(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION internal.complete_live_activity_start(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION internal.fail_live_activity_start(uuid, text, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION internal.claim_live_activity_end(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION internal.complete_live_activity_end(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION internal.fail_live_activity_end(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION internal.claim_live_activity_start(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION internal.complete_live_activity_start(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION internal.fail_live_activity_start(uuid, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION internal.claim_live_activity_end(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION internal.complete_live_activity_end(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION internal.fail_live_activity_end(uuid, text, boolean) TO service_role;
