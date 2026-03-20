-- Function: emit_thread_removed_inbox_event_v2
-- Description: Appends a thread_removed inbox event for a user/thread pair

CREATE OR REPLACE FUNCTION internal.emit_thread_removed_inbox_event_v2(
  p_user_id uuid,
  p_thread_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
BEGIN
  IF p_user_id IS NULL OR p_thread_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM internal.append_inbox_event(
    p_user_id,
    p_thread_id,
    'thread_removed',
    jsonb_build_object(
      'thread_id', p_thread_id,
      'removed_at', now()
    )
  );
END;
$function$;

