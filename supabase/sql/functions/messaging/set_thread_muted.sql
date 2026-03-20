-- Function: set_thread_muted
-- Description: Upserts the caller's muted state for a thread

CREATE OR REPLACE FUNCTION public.set_thread_muted(
  p_thread_id uuid,
  p_muted boolean
)
RETURNS public.thread_user_state
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result public.thread_user_state%ROWTYPE;
  v_existing_muted boolean;
  v_requested_muted boolean := COALESCE(p_muted, false);
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  SELECT tus.muted
  INTO v_existing_muted
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1;

  INSERT INTO public.thread_user_state (
    thread_id,
    user_id,
    muted,
    updated_at
  )
  VALUES (
    p_thread_id,
    v_uid,
    v_requested_muted,
    now()
  )
  ON CONFLICT (thread_id, user_id) DO UPDATE
  SET
    muted = EXCLUDED.muted,
    updated_at = now();

  SELECT *
  INTO v_result
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1;

  IF v_existing_muted IS DISTINCT FROM v_requested_muted OR v_existing_muted IS NULL THEN
    PERFORM internal.emit_thread_upserted_inbox_event_v2(v_uid, p_thread_id);
  END IF;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) FROM public;
REVOKE EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) TO authenticated;
