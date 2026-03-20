-- Function: append_inbox_event
-- Description: Appends a single per-user inbox sync event with a strictly increasing version

CREATE OR REPLACE FUNCTION internal.append_inbox_event(
  p_user_id uuid,
  p_thread_id uuid,
  p_event_type text,
  p_payload jsonb
)
RETURNS internal.inbox_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_state internal.user_inbox_sync_state%ROWTYPE;
  v_event internal.inbox_events%ROWTYPE;
  v_now timestamptz := now();
  v_next_version bigint;
  v_next_retained_from_version bigint;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id is required';
  END IF;

  IF NULLIF(btrim(COALESCE(p_event_type, '')), '') IS NULL THEN
    RAISE EXCEPTION 'event_type is required';
  END IF;

  INSERT INTO internal.user_inbox_sync_state (
    user_id,
    version,
    retained_from_version,
    updated_at
  )
  VALUES (
    p_user_id,
    0,
    0,
    v_now
  )
  ON CONFLICT (user_id) DO NOTHING;

  SELECT *
  INTO v_state
  FROM internal.user_inbox_sync_state uiss
  WHERE uiss.user_id = p_user_id
  FOR UPDATE;

  v_next_version := COALESCE(v_state.version, 0) + 1;
  v_next_retained_from_version := CASE
    WHEN COALESCE(v_state.version, 0) = 0 AND COALESCE(v_state.retained_from_version, 0) = 0 THEN 1
    ELSE COALESCE(v_state.retained_from_version, 0)
  END;

  UPDATE internal.user_inbox_sync_state uiss
  SET
    version = v_next_version,
    retained_from_version = v_next_retained_from_version,
    updated_at = v_now
  WHERE uiss.user_id = p_user_id;

  INSERT INTO internal.inbox_events (
    user_id,
    version,
    thread_id,
    event_type,
    payload,
    created_at
  )
  VALUES (
    p_user_id,
    v_next_version,
    p_thread_id,
    p_event_type,
    COALESCE(p_payload, '{}'::jsonb),
    v_now
  )
  RETURNING *
  INTO v_event;

  RETURN v_event;
END;
$function$;

