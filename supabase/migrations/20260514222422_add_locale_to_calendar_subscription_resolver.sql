BEGIN;

CREATE OR REPLACE FUNCTION internal.calendar_subscription_normalize_locale(
  p_locale text
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_normalized_locale text := pg_catalog.lower(pg_catalog.replace(NULLIF(pg_catalog.btrim(COALESCE(p_locale, '')), ''), '_', '-'));
  v_language text;
  v_supported_languages text[] := ARRAY[
    'ar', 'bg', 'bn', 'ca', 'cs', 'da', 'de', 'el', 'en', 'es', 'et', 'fa',
    'fi', 'fil', 'fr', 'he', 'hi', 'hr', 'hu', 'id', 'is', 'it', 'ja', 'ko',
    'lt', 'lv', 'nb', 'nl', 'nn', 'pl', 'pt', 'pt-br', 'ro', 'ru', 'sk',
    'sl', 'sr', 'sv', 'sw', 'ta', 'th', 'tr', 'uk', 'ur', 'vi', 'zh',
    'zh-hans', 'zh-hant'
  ];
BEGIN
  IF v_normalized_locale IS NULL THEN
    RETURN 'en';
  END IF;

  v_language := CASE
    WHEN v_normalized_locale LIKE 'pt-br%' THEN 'pt-br'
    WHEN v_normalized_locale LIKE 'zh-hans%' THEN 'zh-hans'
    WHEN v_normalized_locale LIKE 'zh-hant%' THEN 'zh-hant'
    WHEN pg_catalog.split_part(v_normalized_locale, '-', 1) = 'no' THEN 'nb'
    ELSE pg_catalog.split_part(v_normalized_locale, '-', 1)
  END;

  IF v_language = ANY(v_supported_languages) THEN
    RETURN v_language;
  END IF;

  RETURN 'en';
END;
$$;

DROP FUNCTION IF EXISTS public.resolve_calendar_subscription_token(text);
DROP FUNCTION IF EXISTS internal.resolve_calendar_subscription_token(text);

CREATE OR REPLACE FUNCTION internal.resolve_calendar_subscription_token(
  p_raw_token text
)
RETURNS TABLE (
  user_id uuid,
  content_mode text,
  locale text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_token_hash text;
BEGIN
  IF p_raw_token IS NULL OR p_raw_token !~ '^tidex_cal_[0-9a-f]{64}$' THEN
    RETURN;
  END IF;

  v_token_hash := internal.calendar_subscription_hash_token(p_raw_token);

  RETURN QUERY
  WITH matched AS (
    SELECT
      cst.id,
      cst.user_id,
      cst.content_mode,
      cst.last_used_at,
      internal.calendar_subscription_normalize_locale(au.raw_user_meta_data->>'locale') AS locale
    FROM internal.calendar_subscription_tokens cst
    LEFT JOIN auth.users au
      ON au.id = cst.user_id
    WHERE cst.token_hash = v_token_hash
      AND cst.revoked_at IS NULL
    LIMIT 1
  ),
  touched AS (
    UPDATE internal.calendar_subscription_tokens cst
    SET last_used_at = now()
    FROM matched
    WHERE cst.id = matched.id
      AND (
        matched.last_used_at IS NULL
        OR matched.last_used_at < now() - interval '15 minutes'
      )
    RETURNING cst.id
  )
  SELECT matched.user_id, matched.content_mode, matched.locale
  FROM matched
  LEFT JOIN touched ON true;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_calendar_subscription_token(
  p_raw_token text
)
RETURNS TABLE (
  user_id uuid,
  content_mode text,
  locale text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT *
  FROM internal.resolve_calendar_subscription_token(p_raw_token);
$$;

COMMENT ON FUNCTION public.resolve_calendar_subscription_token(text) IS
  'Service-role-only RPC wrapper for calendar feed token resolution; returns user_id, content_mode, and normalized feed locale.';

REVOKE ALL ON FUNCTION internal.calendar_subscription_normalize_locale(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.resolve_calendar_subscription_token(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.resolve_calendar_subscription_token(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_calendar_subscription_token(text) FROM anon;
REVOKE ALL ON FUNCTION public.resolve_calendar_subscription_token(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_calendar_subscription_token(text) TO service_role;

COMMIT;
