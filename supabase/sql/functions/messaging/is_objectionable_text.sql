-- Function: is_objectionable_text
-- Description: Conservative text filter for user-generated content safety gates.

CREATE OR REPLACE FUNCTION public.is_objectionable_text(p_text text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_normalized text := regexp_replace(lower(COALESCE(p_text, '')), '[^[:alnum:]]+', ' ', 'g');
BEGIN
  IF btrim(v_normalized) = '' THEN
    RETURN false;
  END IF;

  RETURN v_normalized ~* (
    'kys|' ||
    'kill[[:space:]]+yourself|' ||
    'rape|' ||
    'rapist|' ||
    'porn|' ||
    'pornography|' ||
    'nude[[:space:]]+pics?|' ||
    'send[[:space:]]+nudes?|' ||
    'nigger|' ||
    'nigga|' ||
    'faggot|' ||
    'tranny|' ||
    'retard|' ||
    'heil[[:space:]]+hitler|' ||
    'gas[[:space:]]+the[[:space:]]+jews'
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.is_objectionable_text(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.is_objectionable_text(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.is_objectionable_text(text) TO authenticated;
