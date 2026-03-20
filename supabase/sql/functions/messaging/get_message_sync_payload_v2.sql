-- Function: get_message_sync_payload_v2
-- Description: Returns a caller-shaped V2 message payload for a single message id

CREATE OR REPLACE FUNCTION public.get_message_sync_payload_v2(p_message_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_payload jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT m.thread_id
  INTO v_thread_id
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_thread_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT public.can_access_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  v_payload := internal.build_message_sync_payload_v2(p_message_id);

  IF v_payload IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN internal.shape_message_sync_payload_v2(v_payload, v_uid);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_message_sync_payload_v2(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_message_sync_payload_v2(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_message_sync_payload_v2(uuid) TO authenticated;
