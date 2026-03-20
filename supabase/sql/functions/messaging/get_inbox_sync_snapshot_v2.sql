-- Function: get_inbox_sync_snapshot_v2
-- Description: Returns the caller inbox snapshot page for messaging sync V2

CREATE OR REPLACE FUNCTION public.get_inbox_sync_snapshot_v2(
  p_limit integer DEFAULT 30,
  p_before_last_message_at timestamptz DEFAULT NULL,
  p_before_thread_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_snapshot_version bigint := 0;
  v_retained_from_version bigint := 0;
  v_threads jsonb := '[]'::jsonb;
  v_next_cursor jsonb;
  v_has_more boolean := false;
  v_unread_direct_message_count integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF (p_before_last_message_at IS NULL) <> (p_before_thread_id IS NULL) THEN
    RAISE EXCEPTION 'Pagination cursor requires both before_last_message_at and before_thread_id';
  END IF;

  SELECT
    COALESCE(uiss.version, 0),
    COALESCE(uiss.retained_from_version, 0)
  INTO
    v_snapshot_version,
    v_retained_from_version
  FROM internal.user_inbox_sync_state uiss
  WHERE uiss.user_id = v_uid;

  WITH visible_threads AS (
    SELECT t.id, t.last_message_at
    FROM public.thread_memberships tm
    JOIN public.threads t
      ON t.id = tm.thread_id
    WHERE tm.user_id = v_uid
      AND tm.status = 'active'
      AND internal.can_access_thread_as_user(t.id, v_uid)
      AND (
        p_before_last_message_at IS NULL
        OR (t.last_message_at, t.id) < (p_before_last_message_at, p_before_thread_id)
      )
    ORDER BY t.last_message_at DESC, t.id DESC
    LIMIT v_limit + 1
  ),
  page_threads AS (
    SELECT vt.id, vt.last_message_at
    FROM visible_threads vt
    ORDER BY vt.last_message_at DESC, vt.id DESC
    LIMIT v_limit
  ),
  last_page_row AS (
    SELECT pt.last_message_at, pt.id
    FROM page_threads pt
    ORDER BY pt.last_message_at ASC, pt.id ASC
    LIMIT 1
  )
  SELECT
    COALESCE(
      jsonb_agg(
        internal.build_thread_summary_sync_payload_v2(pt.id, v_uid)
        ORDER BY pt.last_message_at DESC, pt.id DESC
      ),
      '[]'::jsonb
    ),
    EXISTS (
      SELECT 1
      FROM visible_threads vt
      OFFSET v_limit
    ),
    (
      SELECT jsonb_build_object(
        'before_last_message_at', lpr.last_message_at,
        'before_thread_id', lpr.id
      )
      FROM last_page_row lpr
    )
  INTO
    v_threads,
    v_has_more,
    v_next_cursor
  FROM page_threads pt;

  SELECT COALESCE(SUM(COALESCE(tus.unread_count, 0)), 0)::integer
  INTO v_unread_direct_message_count
  FROM public.threads t
  JOIN public.thread_memberships tm
    ON tm.thread_id = t.id
   AND tm.user_id = v_uid
   AND tm.status = 'active'
  LEFT JOIN public.thread_user_state tus
    ON tus.thread_id = t.id
   AND tus.user_id = v_uid
  WHERE t.kind = 'direct'
    AND internal.can_access_thread_as_user(t.id, v_uid);

  RETURN jsonb_build_object(
    'threads', v_threads,
    'unread_direct_message_count', v_unread_direct_message_count,
    'next_cursor', CASE
      WHEN v_has_more THEN v_next_cursor
      ELSE NULL
    END,
    'snapshot_version', v_snapshot_version,
    'retained_from_version', v_retained_from_version,
    'has_more', v_has_more
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_inbox_sync_snapshot_v2(integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_inbox_sync_snapshot_v2(integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_inbox_sync_snapshot_v2(integer, timestamptz, uuid) TO authenticated;

