-- Function: emit_message_reaction_sync_v2
-- Description: Emits V2 thread events for sanctioned reaction inserts and deletes

CREATE OR REPLACE FUNCTION internal.emit_message_reaction_sync_v2()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_message_id uuid := COALESCE(NEW.message_id, OLD.message_id);
  v_thread_id uuid := COALESCE(NEW.thread_id, OLD.thread_id);
  v_actor_user_id uuid := COALESCE(NEW.user_id, OLD.user_id);
BEGIN
  IF current_setting('tidex.messaging_v2_emit_message_reaction', true) IS DISTINCT FROM 'true' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  PERFORM internal.append_thread_event(
    v_thread_id,
    'message_upserted',
    'message',
    v_message_id,
    internal.build_message_sync_payload_v2(v_message_id),
    v_actor_user_id
  );

  RETURN COALESCE(NEW, OLD);
END;
$function$;
