-- Username helpers for the authenticated user's own profile.

CREATE OR REPLACE FUNCTION public.get_my_profile_username()
RETURNS TABLE (
  username text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY
  SELECT p.username
  FROM public.profiles p
  WHERE p.id = v_user_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::text;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_profile_username() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_profile_username() FROM anon;
REVOKE ALL ON FUNCTION public.get_my_profile_username() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_profile_username() TO authenticated;

CREATE OR REPLACE FUNCTION public.set_my_profile_username(p_username text)
RETURNS TABLE (
  username text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_username text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_username := NULLIF(lower(btrim(COALESCE(p_username, ''))), '');

  UPDATE public.profiles
  SET
    username = v_username,
    updated_at = now()
  WHERE id = v_user_id
  RETURNING profiles.username INTO v_username;

  IF NOT FOUND THEN
    INSERT INTO public.profiles (id, username)
    VALUES (v_user_id, v_username)
    RETURNING profiles.username INTO v_username;
  END IF;

  RETURN QUERY SELECT v_username;
END;
$$;

REVOKE ALL ON FUNCTION public.set_my_profile_username(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_my_profile_username(text) FROM anon;
REVOKE ALL ON FUNCTION public.set_my_profile_username(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.set_my_profile_username(text) TO authenticated;
