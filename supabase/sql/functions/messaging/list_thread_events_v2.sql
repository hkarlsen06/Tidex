-- Function: list_thread_events_v2
-- Description: Returns per-thread messaging sync V2 events after a caller-provided version

CREATE OR REPLACE FUNCTION public.list_thread_events_v2(
  p_thread_id uuid,
  p_after_version bigint,
  p_limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 100);
  v_latest_version bigint := 0;
  v_retained_from_version bigint := 0;
  v_requires_snapshot boolean := false;
  v_has_more boolean := false;
  v_events jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_after_version IS NULL OR p_after_version < 0 THEN
    RAISE EXCEPTION 'after_version must be a non-negative bigint';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  SELECT
    COALESCE(t.state_version, 0),
    COALESCE(t.retained_from_version, 0)
  INTO
    v_latest_version,
    v_retained_from_version
  FROM public.threads t
  WHERE t.id = p_thread_id;

  v_requires_snapshot := v_latest_version > 0
    AND p_after_version < GREATEST(v_retained_from_version - 1, 0);

  IF NOT v_requires_snapshot THEN
    WITH selected_events AS (
      SELECT
        te.id,
        te.version,
        te.event_type,
        te.entity_type,
        te.entity_id,
        te.payload,
        te.actor_user_id,
        te.created_at
      FROM internal.thread_events te
      WHERE te.thread_id = p_thread_id
        AND te.version > p_after_version
      ORDER BY te.version ASC
      LIMIT v_limit + 1
    ),
    page_events AS (
      SELECT se.*
      FROM selected_events se
      ORDER BY se.version ASC
      LIMIT v_limit
    )
    SELECT
      COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', pe.id,
            'version', pe.version,
            'event_type', pe.event_type,
            'entity_type', pe.entity_type,
            'entity_id', pe.entity_id,
            'created_at', pe.created_at,
            'actor_user_id', pe.actor_user_id,
            'payload', CASE
              WHEN pe.event_type = 'message_upserted' THEN
                internal.shape_message_sync_payload_v2(pe.payload, v_uid)
              ELSE
                pe.payload
            END
          )
          ORDER BY pe.version ASC
        ),
        '[]'::jsonb
      ),
      EXISTS (
        SELECT 1
        FROM selected_events se
        OFFSET v_limit
      )
    INTO
      v_events,
      v_has_more
    FROM page_events pe;
  END IF;

  RETURN jsonb_build_object(
    'requires_snapshot', v_requires_snapshot,
    'latest_version', v_latest_version,
    'retained_from_version', v_retained_from_version,
    'has_more', CASE
      WHEN v_requires_snapshot THEN false
      ELSE v_has_more
    END,
    'events', CASE
      WHEN v_requires_snapshot THEN '[]'::jsonb
      ELSE v_events
    END
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_thread_events_v2(uuid, bigint, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_thread_events_v2(uuid, bigint, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_thread_events_v2(uuid, bigint, integer) TO authenticated;

