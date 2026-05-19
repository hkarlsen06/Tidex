CREATE OR REPLACE FUNCTION public.unregister_push_device(p_fcm_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  DELETE FROM internal.push_devices
  WHERE fcm_token = p_fcm_token
    AND user_id = v_user_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.unregister_push_device(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.unregister_push_device(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.unregister_push_device(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_push_device_last_seen(p_fcm_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  UPDATE internal.push_devices
  SET last_seen_at = now()
  WHERE fcm_token = p_fcm_token
    AND user_id = v_user_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.update_push_device_last_seen(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.update_push_device_last_seen(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_push_device_last_seen(text) TO authenticated;
