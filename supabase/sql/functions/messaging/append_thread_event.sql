-- Function: append_thread_event
-- Description: Appends a single per-thread sync event with a strictly increasing version

CREATE OR REPLACE FUNCTION internal.append_thread_event(
  p_thread_id uuid,
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid,
  p_payload jsonb,
  p_actor_user_id uuid DEFAULT NULL
)
RETURNS internal.thread_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_thread public.threads%ROWTYPE;
  v_event internal.thread_events%ROWTYPE;
  v_now timestamptz := now();
  v_next_version bigint;
  v_next_retained_from_version bigint;
BEGIN
  IF p_thread_id IS NULL THEN
    RAISE EXCEPTION 'thread_id is required';
  END IF;

  IF NULLIF(btrim(COALESCE(p_event_type, '')), '') IS NULL THEN
    RAISE EXCEPTION 'event_type is required';
  END IF;

  IF NULLIF(btrim(COALESCE(p_entity_type, '')), '') IS NULL THEN
    RAISE EXCEPTION 'entity_type is required';
  END IF;

  SELECT *
  INTO v_thread
  FROM public.threads t
  WHERE t.id = p_thread_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Thread not found';
  END IF;

  v_next_version := COALESCE(v_thread.state_version, 0) + 1;
  v_next_retained_from_version := CASE
    WHEN COALESCE(v_thread.state_version, 0) = 0 AND COALESCE(v_thread.retained_from_version, 0) = 0 THEN 1
    ELSE COALESCE(v_thread.retained_from_version, 0)
  END;

  UPDATE public.threads t
  SET
    state_version = v_next_version,
    retained_from_version = v_next_retained_from_version
  WHERE t.id = p_thread_id;

  INSERT INTO internal.thread_events (
    thread_id,
    version,
    event_type,
    entity_type,
    entity_id,
    payload,
    actor_user_id,
    created_at
  )
  VALUES (
    p_thread_id,
    v_next_version,
    p_event_type,
    p_entity_type,
    p_entity_id,
    COALESCE(p_payload, '{}'::jsonb),
    p_actor_user_id,
    v_now
  )
  RETURNING *
  INTO v_event;

  RETURN v_event;
END;
$function$;

