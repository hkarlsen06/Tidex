BEGIN;

ALTER TABLE IF EXISTS public.profiles
  ADD COLUMN IF NOT EXISTS username text;

UPDATE public.profiles
SET username = lower(btrim(username))
WHERE username IS NOT NULL;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_username_format;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_username_format
  CHECK (
    username IS NULL
    OR (
      username = lower(btrim(username))
      AND username = btrim(username)
      AND char_length(username) BETWEEN 3 AND 20
      AND username ~ '^[a-z0-9_]+$'
      AND username ~ '[a-z]'
    )
  );

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_username_unique
  ON public.profiles (username)
  WHERE username IS NOT NULL;

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

CREATE OR REPLACE FUNCTION public.manage_sharing_action(
  p_action text,
  p_identifier text DEFAULT NULL,
  p_recipient_id uuid DEFAULT NULL,
  p_show_earnings boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_limit integer := 1;
  v_target_id uuid;
  v_normalized text;
  v_identifier text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT CASE COALESCE(tier, 'free')
    WHEN 'max' THEN 20
    WHEN 'pro' THEN 10
    ELSE 1
  END
  INTO v_limit
  FROM public.user_entitlements
  WHERE user_id = v_user_id;

  IF (SELECT COUNT(*) FROM public.shift_shares WHERE owner_id = v_user_id) >= v_limit THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Du har nådd maksimalt antall delinger for ditt abonnement'
    );
  END IF;

  IF p_action = 'createShare' THEN
    IF p_identifier IS NULL OR btrim(p_identifier) = '' THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Vennligst oppgi en gyldig e-post, telefonnummer eller brukernavn'
      );
    END IF;

    v_identifier := btrim(p_identifier);

    IF position('@' IN v_identifier) > 0 AND left(v_identifier, 1) <> '@' THEN
      SELECT id INTO v_target_id
      FROM auth.users
      WHERE lower(email) = lower(v_identifier)
      LIMIT 1;
    ELSE
      v_identifier := lower(v_identifier);
      IF left(v_identifier, 1) = '@' THEN
        v_identifier := substr(v_identifier, 2);
      END IF;

      SELECT id INTO v_target_id
      FROM public.profiles
      WHERE username = v_identifier
      LIMIT 1;

      IF v_target_id IS NULL THEN
        v_normalized := regexp_replace(p_identifier, '\D', '', 'g');
        IF length(v_normalized) = 8 THEN
          v_normalized := '47' || v_normalized;
        ELSIF left(v_normalized, 2) = '00' THEN
          v_normalized := substr(v_normalized, 3);
        END IF;

        SELECT id INTO v_target_id
        FROM auth.users
        WHERE phone = v_normalized
        LIMIT 1;
      END IF;
    END IF;
  ELSIF p_action = 'shareBack' THEN
    v_target_id := p_recipient_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Ugyldig handling');
  END IF;

  IF v_target_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Fant ingen bruker med denne e-posten, telefonnummeret eller brukernavnet'
    );
  END IF;

  IF v_target_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du kan ikke dele med deg selv');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.shift_shares
    WHERE owner_id = v_user_id
      AND viewer_id = v_target_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du deler allerede vaktene dine med denne brukeren');
  END IF;

  INSERT INTO public.shift_shares (
    owner_id,
    viewer_id,
    show_earnings,
    muted,
    owner_muted
  ) VALUES (
    v_user_id,
    v_target_id,
    COALESCE(p_show_earnings, false),
    false,
    false
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

COMMIT;
