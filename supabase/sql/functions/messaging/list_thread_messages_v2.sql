-- Function: list_thread_messages_v2
-- Description: Returns a V2-shaped message history page for a thread with stable keyset pagination

CREATE OR REPLACE FUNCTION public.list_thread_messages_v2(
  p_thread_id uuid,
  p_limit integer DEFAULT 50,
  p_before_created_at timestamptz DEFAULT NULL,
  p_before_message_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
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

  IF (p_before_created_at IS NULL) <> (p_before_message_id IS NULL) THEN
    RAISE EXCEPTION 'Pagination cursor requires both before_created_at and before_message_id';
  END IF;

  WITH selected_messages AS (
    SELECT m.id, m.created_at
    FROM public.messages m
    WHERE m.thread_id = p_thread_id
      AND m.deleted_at IS NULL
      AND (
        p_before_created_at IS NULL
        OR (m.created_at, m.id) < (p_before_created_at, p_before_message_id)
      )
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
    v_has_more;

  RETURN jsonb_build_object(
    'messages', v_messages_payload,
    'next_cursor', CASE
      WHEN v_has_more THEN v_next_cursor
      ELSE NULL
    END,
    'has_more', v_has_more
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_thread_messages_v2(uuid, integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_thread_messages_v2(uuid, integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_thread_messages_v2(uuid, integer, timestamptz, uuid) TO authenticated;
