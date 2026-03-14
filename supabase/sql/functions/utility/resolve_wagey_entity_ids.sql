-- Resolve Wagey short IDs to full UUIDs without scanning rows in the edge function.

CREATE OR REPLACE FUNCTION public.resolve_user_shift_id(p_short_or_full_id text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_result uuid;
  v_matches uuid[];
BEGIN
  IF v_user_id IS NULL OR p_short_or_full_id IS NULL OR btrim(p_short_or_full_id) = '' THEN
    RETURN NULL;
  END IF;

  IF p_short_or_full_id ~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' THEN
    SELECT us.id
    INTO v_result
    FROM public.user_shifts us
    WHERE us.id = p_short_or_full_id::uuid
      AND us.user_id = v_user_id
      AND us.deleted_at IS NULL
    LIMIT 1;

    RETURN v_result;
  END IF;

  IF p_short_or_full_id !~* '^[a-f0-9]{4,8}$' THEN
    RETURN NULL;
  END IF;

  SELECT array_agg(match.id)
  INTO v_matches
  FROM (
    SELECT us.id
    FROM public.user_shifts us
    WHERE us.user_id = v_user_id
      AND us.deleted_at IS NULL
      AND us.id::text LIKE lower(p_short_or_full_id) || '%'
    ORDER BY us.id
    LIMIT 2
  ) AS match;

  IF coalesce(array_length(v_matches, 1), 0) = 1 THEN
    RETURN v_matches[1];
  END IF;

  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_recurring_shift_id(p_short_or_full_id text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_result uuid;
  v_matches uuid[];
BEGIN
  IF v_user_id IS NULL OR p_short_or_full_id IS NULL OR btrim(p_short_or_full_id) = '' THEN
    RETURN NULL;
  END IF;

  IF p_short_or_full_id ~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' THEN
    SELECT rs.id
    INTO v_result
    FROM public.recurring_shifts rs
    WHERE rs.id = p_short_or_full_id::uuid
      AND rs.user_id = v_user_id
      AND rs.deleted_at IS NULL
    LIMIT 1;

    RETURN v_result;
  END IF;

  IF p_short_or_full_id !~* '^[a-f0-9]{4,8}$' THEN
    RETURN NULL;
  END IF;

  SELECT array_agg(match.id)
  INTO v_matches
  FROM (
    SELECT rs.id
    FROM public.recurring_shifts rs
    WHERE rs.user_id = v_user_id
      AND rs.deleted_at IS NULL
      AND rs.id::text LIKE lower(p_short_or_full_id) || '%'
    ORDER BY rs.id
    LIMIT 2
  ) AS match;

  IF coalesce(array_length(v_matches, 1), 0) = 1 THEN
    RETURN v_matches[1];
  END IF;

  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_wage_snapshot_id(p_short_or_full_id text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_result uuid;
  v_matches uuid[];
BEGIN
  IF v_user_id IS NULL OR p_short_or_full_id IS NULL OR btrim(p_short_or_full_id) = '' THEN
    RETURN NULL;
  END IF;

  IF p_short_or_full_id ~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' THEN
    SELECT ws.id
    INTO v_result
    FROM public.wage_snapshots ws
    WHERE ws.id = p_short_or_full_id::uuid
      AND ws.user_id = v_user_id
      AND ws.deleted_at IS NULL
    LIMIT 1;

    RETURN v_result;
  END IF;

  IF p_short_or_full_id !~* '^[a-f0-9]{4,8}$' THEN
    RETURN NULL;
  END IF;

  SELECT array_agg(match.id)
  INTO v_matches
  FROM (
    SELECT ws.id
    FROM public.wage_snapshots ws
    WHERE ws.user_id = v_user_id
      AND ws.deleted_at IS NULL
      AND ws.id::text LIKE lower(p_short_or_full_id) || '%'
    ORDER BY ws.id
    LIMIT 2
  ) AS match;

  IF coalesce(array_length(v_matches, 1), 0) = 1 THEN
    RETURN v_matches[1];
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_user_shift_id(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_user_shift_id(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_user_shift_id(text) TO authenticated;

REVOKE ALL ON FUNCTION public.resolve_recurring_shift_id(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_recurring_shift_id(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_recurring_shift_id(text) TO authenticated;

REVOKE ALL ON FUNCTION public.resolve_wage_snapshot_id(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_wage_snapshot_id(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_wage_snapshot_id(text) TO authenticated;
