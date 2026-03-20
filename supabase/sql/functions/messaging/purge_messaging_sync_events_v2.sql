-- Function: purge_messaging_sync_events_v2
-- Description: Purges old messaging sync V2 events and advances retained-from markers

CREATE OR REPLACE FUNCTION internal.purge_messaging_sync_events_v2(
  p_retention interval DEFAULT interval '30 days'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_cutoff timestamptz := now() - COALESCE(p_retention, interval '30 days');
  v_deleted_thread_events integer := 0;
  v_deleted_inbox_events integer := 0;
BEGIN
  DELETE FROM internal.thread_events te
  WHERE te.created_at < v_cutoff;
  GET DIAGNOSTICS v_deleted_thread_events = ROW_COUNT;

  DELETE FROM internal.inbox_events ie
  WHERE ie.created_at < v_cutoff;
  GET DIAGNOSTICS v_deleted_inbox_events = ROW_COUNT;

  UPDATE public.threads t
  SET retained_from_version = CASE
    WHEN t.state_version = 0 THEN 0
    ELSE COALESCE(
      (
        SELECT MIN(te.version)
        FROM internal.thread_events te
        WHERE te.thread_id = t.id
      ),
      t.state_version + 1
    )
  END
  WHERE t.state_version > 0;

  UPDATE internal.user_inbox_sync_state uiss
  SET retained_from_version = CASE
    WHEN uiss.version = 0 THEN 0
    ELSE COALESCE(
      (
        SELECT MIN(ie.version)
        FROM internal.inbox_events ie
        WHERE ie.user_id = uiss.user_id
      ),
      uiss.version + 1
    )
  END;

  RETURN jsonb_build_object(
    'cutoff', v_cutoff,
    'deleted_thread_events', v_deleted_thread_events,
    'deleted_inbox_events', v_deleted_inbox_events
  );
END;
$function$;

