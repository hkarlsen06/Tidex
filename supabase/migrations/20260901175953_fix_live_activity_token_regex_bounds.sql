-- Fix Live Activity token validation: '{32,512}' exceeds PostgreSQL's regex
-- repetition-bound limit of 255, so these checks raised 'invalid regular
-- expression' (SQLSTATE 2201B) on every call since 20260720214331. Validate
-- length with char_length and keep the regex to the character class only.

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
     OR char_length(p_push_to_start_token) NOT BETWEEN 32 AND 512
     OR p_push_to_start_token !~ '^[0-9A-Fa-f]+$' THEN
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
     OR char_length(p_push_token) NOT BETWEEN 32 AND 512
     OR p_push_token !~ '^[0-9A-Fa-f]+$' THEN
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
