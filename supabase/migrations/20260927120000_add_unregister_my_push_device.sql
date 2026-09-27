-- Removes the caller's own push device row for an APNs (or FCM) token.
-- The iOS app calls this before sign-out so the device stops receiving the
-- previous user's notifications.
CREATE OR REPLACE FUNCTION public.unregister_my_push_device(p_device_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  IF NULLIF(p_device_token, '') IS NULL THEN
    RETURN;
  END IF;

  DELETE FROM internal.push_devices
  WHERE user_id = v_user_id
    AND (apns_token = p_device_token OR fcm_token = p_device_token);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.unregister_my_push_device(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.unregister_my_push_device(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.unregister_my_push_device(text) TO authenticated;
