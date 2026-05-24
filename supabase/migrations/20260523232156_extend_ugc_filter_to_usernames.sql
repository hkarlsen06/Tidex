-- Extend the UGC safety filter and enforce it for profile usernames.

CREATE OR REPLACE FUNCTION public.is_objectionable_text(p_text text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_normalized text := regexp_replace(
    replace(
      replace(
        replace(lower(COALESCE(p_text, '')), 'æ', 'ae'),
        'ø',
        'o'
      ),
      'å',
      'a'
    ),
    '[^[:alnum:]]+',
    ' ',
    'g'
  );
BEGIN
  IF btrim(v_normalized) = '' THEN
    RETURN false;
  END IF;

  RETURN v_normalized ~* (
    'kys|' ||
    'kill[[:space:]]+yourself|' ||
    'suicide|' ||
    'selvmord|' ||
    'ta[[:space:]]+livet[[:space:]]+ditt|' ||
    'drep[[:space:]]+deg[[:space:]]+selv|' ||
    'rape|' ||
    'rapist|' ||
    'voldtekt|' ||
    'voldtektsmann|' ||
    'porn|' ||
    'pornography|' ||
    'porno|' ||
    'pedophile|' ||
    'pedofil|' ||
    'pedo|' ||
    'nude[[:space:]]+pics?|' ||
    'send[[:space:]]+nudes?|' ||
    'send[[:space:]]+nakenbilder|' ||
    'nakenbilder|' ||
    'nigger|' ||
    'nigga|' ||
    'faggot|' ||
    'homo|' ||
    'tranny|' ||
    'retard|' ||
    'tilbakestaende|' ||
    'heil[[:space:]]+hitler|' ||
    'nazi|' ||
    'nazist|' ||
    'gas[[:space:]]+the[[:space:]]+jews|' ||
    'gass[[:space:]]+jodene|' ||
    'jodeutryddelse|' ||
    'neger|' ||
    'svarting|' ||
    'pakkis|' ||
    'jaevla[[:space:]]+utlending|' ||
    'hore|' ||
    'fitte|' ||
    'kuk'
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.is_objectionable_text(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.is_objectionable_text(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.is_objectionable_text(text) TO authenticated;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_username_safety_filter;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_username_safety_filter
  CHECK (username IS NULL OR NOT public.is_objectionable_text(username))
  NOT VALID;

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

  IF public.is_objectionable_text(v_username) THEN
    RAISE EXCEPTION 'Username blocked by safety filter';
  END IF;

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
