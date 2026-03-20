-- Function: emit_thread_upserted_inbox_event_v2
-- Description: Appends a thread_upserted inbox event for a visible user/thread pair

CREATE OR REPLACE FUNCTION internal.emit_thread_upserted_inbox_event_v2(
  p_user_id uuid,
  p_thread_id uuid,
  p_use_last_message_override boolean DEFAULT false,
  p_last_message_id uuid DEFAULT NULL,
  p_last_message_sender_id uuid DEFAULT NULL,
  p_last_message_at timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_payload jsonb;
BEGIN
  v_payload := internal.build_thread_summary_sync_payload_v2(
    p_thread_id,
    p_user_id,
    p_use_last_message_override,
    p_last_message_id,
    p_last_message_sender_id,
    p_last_message_at
  );

  IF v_payload IS NULL THEN
    RETURN;
  END IF;

  PERFORM internal.append_inbox_event(
    p_user_id,
    p_thread_id,
    'thread_upserted',
    v_payload
  );
END;
$function$;

