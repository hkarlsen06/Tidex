CREATE OR REPLACE FUNCTION internal.calendar_subscription_assert_content_mode(
  p_content_mode text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_content_mode text := NULLIF(btrim(COALESCE(p_content_mode, '')), '');
BEGIN
  IF v_content_mode NOT IN ('events_only', 'shifts_only', 'shifts_and_events') THEN
    RAISE EXCEPTION 'invalid calendar subscription content mode'
      USING ERRCODE = '22023';
  END IF;

  RETURN v_content_mode;
END;
$$;

CREATE OR REPLACE FUNCTION internal.calendar_subscription_hash_token(
  p_raw_token text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT encode(extensions.digest(p_raw_token, 'sha256'), 'hex');
$$;

CREATE OR REPLACE FUNCTION internal.calendar_subscription_generate_token()
RETURNS TABLE (
  raw_token text,
  token_hash text,
  token_suffix text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  raw_token := 'tidex_cal_' || encode(extensions.gen_random_bytes(32), 'hex');
  token_hash := internal.calendar_subscription_hash_token(raw_token);
  token_suffix := right(raw_token, 8);
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION internal.get_my_calendar_subscription()
RETURNS TABLE (
  is_active boolean,
  id uuid,
  content_mode text,
  token_suffix text,
  created_at timestamptz,
  updated_at timestamptz,
  last_used_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    true,
    cst.id,
    cst.content_mode,
    cst.token_suffix,
    cst.created_at,
    cst.updated_at,
    cst.last_used_at
  FROM internal.calendar_subscription_tokens cst
  WHERE cst.user_id = v_user_id
    AND cst.revoked_at IS NULL
  ORDER BY cst.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY
    SELECT
      false,
      NULL::uuid,
      NULL::text,
      NULL::text,
      NULL::timestamptz,
      NULL::timestamptz,
      NULL::timestamptz;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION internal.create_my_calendar_subscription(
  p_content_mode text DEFAULT 'shifts_only'
)
RETURNS TABLE (
  id uuid,
  raw_token text,
  content_mode text,
  token_suffix text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_content_mode text;
  v_token record;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text, 0));

  v_content_mode := internal.calendar_subscription_assert_content_mode(p_content_mode);

  IF EXISTS (
    SELECT 1
    FROM internal.calendar_subscription_tokens cst
    WHERE cst.user_id = v_user_id
      AND cst.revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'active calendar subscription already exists'
      USING ERRCODE = '23505';
  END IF;

  SELECT *
  INTO v_token
  FROM internal.calendar_subscription_generate_token();

  RETURN QUERY
  INSERT INTO internal.calendar_subscription_tokens AS cst (
    user_id,
    token_hash,
    token_suffix,
    content_mode
  )
  VALUES (
    v_user_id,
    v_token.token_hash,
    v_token.token_suffix,
    v_content_mode
  )
  RETURNING
    cst.id,
    v_token.raw_token,
    cst.content_mode,
    cst.token_suffix,
    cst.created_at;
END;
$$;

CREATE OR REPLACE FUNCTION internal.rotate_my_calendar_subscription(
  p_content_mode text DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  raw_token text,
  content_mode text,
  token_suffix text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_existing internal.calendar_subscription_tokens%ROWTYPE;
  v_content_mode text;
  v_token record;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text, 0));

  SELECT *
  INTO v_existing
  FROM internal.calendar_subscription_tokens cst
  WHERE cst.user_id = v_user_id
    AND cst.revoked_at IS NULL
  ORDER BY cst.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no active calendar subscription'
      USING ERRCODE = 'P0002';
  END IF;

  v_content_mode := internal.calendar_subscription_assert_content_mode(
    COALESCE(p_content_mode, v_existing.content_mode)
  );

  UPDATE internal.calendar_subscription_tokens cst
  SET
    revoked_at = now(),
    updated_at = now()
  WHERE cst.id = v_existing.id;

  SELECT *
  INTO v_token
  FROM internal.calendar_subscription_generate_token();

  RETURN QUERY
  INSERT INTO internal.calendar_subscription_tokens AS cst (
    user_id,
    token_hash,
    token_suffix,
    content_mode
  )
  VALUES (
    v_user_id,
    v_token.token_hash,
    v_token.token_suffix,
    v_content_mode
  )
  RETURNING
    cst.id,
    v_token.raw_token,
    cst.content_mode,
    cst.token_suffix,
    cst.created_at;
END;
$$;

CREATE OR REPLACE FUNCTION internal.set_my_calendar_subscription_content_mode(
  p_content_mode text
)
RETURNS TABLE (
  is_active boolean,
  id uuid,
  content_mode text,
  token_suffix text,
  created_at timestamptz,
  updated_at timestamptz,
  last_used_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_content_mode text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text, 0));

  v_content_mode := internal.calendar_subscription_assert_content_mode(p_content_mode);

  RETURN QUERY
  UPDATE internal.calendar_subscription_tokens cst
  SET
    content_mode = v_content_mode,
    updated_at = now()
  WHERE cst.user_id = v_user_id
    AND cst.revoked_at IS NULL
  RETURNING
    true,
    cst.id,
    cst.content_mode,
    cst.token_suffix,
    cst.created_at,
    cst.updated_at,
    cst.last_used_at;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no active calendar subscription'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION internal.disable_my_calendar_subscription()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_row_count bigint := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text, 0));

  UPDATE internal.calendar_subscription_tokens cst
  SET
    revoked_at = now(),
    updated_at = now()
  WHERE cst.user_id = v_user_id
    AND cst.revoked_at IS NULL;

  GET DIAGNOSTICS v_row_count = ROW_COUNT;

  RETURN v_row_count > 0;
END;
$$;

CREATE OR REPLACE FUNCTION internal.resolve_calendar_subscription_token(
  p_raw_token text
)
RETURNS TABLE (
  user_id uuid,
  content_mode text
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
    SELECT cst.id, cst.user_id, cst.content_mode, cst.last_used_at
    FROM internal.calendar_subscription_tokens cst
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
  SELECT matched.user_id, matched.content_mode
  FROM matched
  LEFT JOIN touched ON true;
END;
$$;

-- Public RPC wrappers intentionally contain no privileged data access logic.
-- They exist only because Supabase/PostgREST exposes RPCs from configured API schemas.
CREATE OR REPLACE FUNCTION public.get_my_calendar_subscription()
RETURNS TABLE (
  is_active boolean,
  id uuid,
  content_mode text,
  token_suffix text,
  created_at timestamptz,
  updated_at timestamptz,
  last_used_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT *
  FROM internal.get_my_calendar_subscription();
$$;

CREATE OR REPLACE FUNCTION public.create_my_calendar_subscription(
  p_content_mode text DEFAULT 'shifts_only'
)
RETURNS TABLE (
  id uuid,
  raw_token text,
  content_mode text,
  token_suffix text,
  created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT *
  FROM internal.create_my_calendar_subscription(p_content_mode);
$$;

CREATE OR REPLACE FUNCTION public.rotate_my_calendar_subscription(
  p_content_mode text DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  raw_token text,
  content_mode text,
  token_suffix text,
  created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT *
  FROM internal.rotate_my_calendar_subscription(p_content_mode);
$$;

CREATE OR REPLACE FUNCTION public.set_my_calendar_subscription_content_mode(
  p_content_mode text
)
RETURNS TABLE (
  is_active boolean,
  id uuid,
  content_mode text,
  token_suffix text,
  created_at timestamptz,
  updated_at timestamptz,
  last_used_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT *
  FROM internal.set_my_calendar_subscription_content_mode(p_content_mode);
$$;

CREATE OR REPLACE FUNCTION public.disable_my_calendar_subscription()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT internal.disable_my_calendar_subscription();
$$;

CREATE OR REPLACE FUNCTION public.resolve_calendar_subscription_token(
  p_raw_token text
)
RETURNS TABLE (
  user_id uuid,
  content_mode text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT *
  FROM internal.resolve_calendar_subscription_token(p_raw_token);
$$;

COMMENT ON FUNCTION public.get_my_calendar_subscription() IS
  'Thin SECURITY DEFINER RPC wrapper around internal calendar subscription implementation; no direct table access logic lives in the exposed schema.';
COMMENT ON FUNCTION public.create_my_calendar_subscription(text) IS
  'Thin SECURITY DEFINER RPC wrapper around internal calendar subscription implementation; returns the raw bearer token only at creation time.';
COMMENT ON FUNCTION public.rotate_my_calendar_subscription(text) IS
  'Thin SECURITY DEFINER RPC wrapper around internal calendar subscription implementation; returns the raw bearer token only at rotation time.';
COMMENT ON FUNCTION public.set_my_calendar_subscription_content_mode(text) IS
  'Thin SECURITY DEFINER RPC wrapper around internal calendar subscription implementation; mutates only the active token content mode.';
COMMENT ON FUNCTION public.disable_my_calendar_subscription() IS
  'Thin SECURITY DEFINER RPC wrapper around internal calendar subscription implementation; revokes the active token when present.';
COMMENT ON FUNCTION public.resolve_calendar_subscription_token(text) IS
  'Service-role-only RPC wrapper for future calendar feed token resolution.';

REVOKE ALL ON FUNCTION internal.calendar_subscription_assert_content_mode(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.calendar_subscription_hash_token(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.calendar_subscription_generate_token() FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.get_my_calendar_subscription() FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.create_my_calendar_subscription(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.rotate_my_calendar_subscription(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.set_my_calendar_subscription_content_mode(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.disable_my_calendar_subscription() FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.resolve_calendar_subscription_token(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.get_my_calendar_subscription() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_calendar_subscription() FROM anon;
REVOKE ALL ON FUNCTION public.get_my_calendar_subscription() FROM service_role;
GRANT EXECUTE ON FUNCTION public.get_my_calendar_subscription() TO authenticated;

REVOKE ALL ON FUNCTION public.create_my_calendar_subscription(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_my_calendar_subscription(text) FROM anon;
REVOKE ALL ON FUNCTION public.create_my_calendar_subscription(text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.create_my_calendar_subscription(text) TO authenticated;

REVOKE ALL ON FUNCTION public.rotate_my_calendar_subscription(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rotate_my_calendar_subscription(text) FROM anon;
REVOKE ALL ON FUNCTION public.rotate_my_calendar_subscription(text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.rotate_my_calendar_subscription(text) TO authenticated;

REVOKE ALL ON FUNCTION public.set_my_calendar_subscription_content_mode(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_my_calendar_subscription_content_mode(text) FROM anon;
REVOKE ALL ON FUNCTION public.set_my_calendar_subscription_content_mode(text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.set_my_calendar_subscription_content_mode(text) TO authenticated;

REVOKE ALL ON FUNCTION public.disable_my_calendar_subscription() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.disable_my_calendar_subscription() FROM anon;
REVOKE ALL ON FUNCTION public.disable_my_calendar_subscription() FROM service_role;
GRANT EXECUTE ON FUNCTION public.disable_my_calendar_subscription() TO authenticated;

REVOKE ALL ON FUNCTION public.resolve_calendar_subscription_token(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_calendar_subscription_token(text) FROM anon;
REVOKE ALL ON FUNCTION public.resolve_calendar_subscription_token(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_calendar_subscription_token(text) TO service_role;
