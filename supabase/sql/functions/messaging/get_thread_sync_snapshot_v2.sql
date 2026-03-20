-- Function: get_thread_sync_snapshot_v2
-- Description: Returns a privacy-safe thread snapshot and initial message page for messaging sync V2

CREATE OR REPLACE FUNCTION public.get_thread_sync_snapshot_v2(
  p_thread_id uuid,
  p_message_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_message_limit, 50), 1), 100);
  v_snapshot_version bigint := 0;
  v_retained_from_version bigint := 0;
  v_thread_payload jsonb;
  v_viewer_state_payload jsonb;
  v_counterpart_payload jsonb;
  v_messages_payload jsonb := '[]'::jsonb;
  v_next_cursor jsonb;
  v_has_more boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  SELECT
    t.state_version,
    t.retained_from_version
  INTO
    v_snapshot_version,
    v_retained_from_version
  FROM public.threads t
  WHERE t.id = p_thread_id;

  v_thread_payload := internal.build_thread_core_sync_payload_v2(p_thread_id);
  v_viewer_state_payload := internal.build_thread_user_state_sync_payload_v2(p_thread_id, v_uid);
  v_counterpart_payload := internal.build_direct_thread_counterpart_sync_payload_v2(p_thread_id, v_uid);

  WITH selected_messages AS (
    SELECT m.id, m.created_at
    FROM public.messages m
    WHERE m.thread_id = p_thread_id
      AND m.deleted_at IS NULL
    ORDER BY m.created_at DESC, m.id DESC
    LIMIT v_limit + 1
  ),
  page_messages AS (
    SELECT sm.id, sm.created_at
    FROM selected_messages sm
    ORDER BY sm.created_at DESC, sm.id DESC
    LIMIT v_limit
  ),
  ordered_messages AS (
    SELECT pm.id, pm.created_at
    FROM page_messages pm
    ORDER BY pm.created_at ASC, pm.id ASC
  ),
  page_bounds AS (
    SELECT
      EXISTS (
        SELECT 1
        FROM selected_messages sm
        OFFSET v_limit
      ) AS has_more,
      (
        SELECT jsonb_build_object(
          'before_created_at', om.created_at,
          'before_message_id', om.id
        )
        FROM ordered_messages om
        ORDER BY om.created_at ASC, om.id ASC
        LIMIT 1
      ) AS next_cursor
  )
  SELECT
    COALESCE((
      SELECT jsonb_agg(
        internal.shape_message_sync_payload_v2(
          internal.build_message_sync_payload_v2(om.id),
          v_uid
        )
        ORDER BY om.created_at ASC, om.id ASC
      )
      FROM ordered_messages om
    ), '[]'::jsonb),
    (
      SELECT pb.next_cursor
      FROM page_bounds pb
    ),
    COALESCE((
      SELECT pb.has_more
      FROM page_bounds pb
    ), false)
  INTO
    v_messages_payload,
    v_next_cursor,
    v_has_more
  ;

  RETURN jsonb_build_object(
    'thread', v_thread_payload,
    'viewer_state', v_viewer_state_payload,
    'counterpart_state', v_counterpart_payload,
    'messages', v_messages_payload,
    'next_cursor', CASE
      WHEN v_has_more THEN v_next_cursor
      ELSE NULL
    END,
    'snapshot_version', COALESCE(v_snapshot_version, 0),
    'retained_from_version', COALESCE(v_retained_from_version, 0),
    'has_more', v_has_more
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_thread_sync_snapshot_v2(uuid, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_thread_sync_snapshot_v2(uuid, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_thread_sync_snapshot_v2(uuid, integer) TO authenticated;
