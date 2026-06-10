-- Updates the authenticated user's best-effort SyncCoordinator heartbeat.

CREATE OR REPLACE FUNCTION public.update_my_profile_last_synced_at(
  p_last_synced_at timestamp with time zone DEFAULT now()
)
RETURNS timestamp with time zone
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_last_synced_at timestamp with time zone;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_last_synced_at := COALESCE(p_last_synced_at, now());

  UPDATE public.profiles
  SET
    last_synced_at = v_last_synced_at,
    updated_at = now()
  WHERE id = v_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.profiles (id, last_synced_at)
    VALUES (v_user_id, v_last_synced_at);
  END IF;

  RETURN v_last_synced_at;
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_profile_last_synced_at(timestamp with time zone)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_my_profile_last_synced_at(timestamp with time zone)
  FROM anon;
REVOKE ALL ON FUNCTION public.update_my_profile_last_synced_at(timestamp with time zone)
  FROM authenticated;
GRANT EXECUTE ON FUNCTION public.update_my_profile_last_synced_at(timestamp with time zone)
  TO authenticated;
