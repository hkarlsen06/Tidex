-- Function: list_inbox_events_v2
-- Description: Returns per-user inbox sync V2 events after a caller-provided version

CREATE OR REPLACE FUNCTION public.list_inbox_events_v2(
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

  SELECT
    COALESCE(uiss.version, 0),
    COALESCE(uiss.retained_from_version, 0)
  INTO
    v_latest_version,
    v_retained_from_version
  FROM internal.user_inbox_sync_state uiss
  WHERE uiss.user_id = v_uid;

  v_requires_snapshot := v_latest_version > 0
    AND p_after_version < GREATEST(v_retained_from_version - 1, 0);

  IF NOT v_requires_snapshot THEN
    WITH selected_events AS (
      SELECT
        ie.id,
        ie.version,
        ie.thread_id,
        ie.event_type,
        ie.payload,
        ie.created_at
      FROM internal.inbox_events ie
      WHERE ie.user_id = v_uid
        AND ie.version > p_after_version
      ORDER BY ie.version ASC
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
            'thread_id', pe.thread_id,
            'event_type', pe.event_type,
            'created_at', pe.created_at,
            'payload', pe.payload
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

REVOKE EXECUTE ON FUNCTION public.list_inbox_events_v2(bigint, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_inbox_events_v2(bigint, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_inbox_events_v2(bigint, integer) TO authenticated;

