CREATE OR REPLACE FUNCTION public.resolve_payroll_adjustment_id(p_short_or_full_id text)
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
    SELECT pa.id
    INTO v_result
    FROM public.payroll_adjustments pa
    WHERE pa.id = p_short_or_full_id::uuid
      AND pa.user_id = v_user_id
      AND pa.deleted_at IS NULL
    LIMIT 1;

    RETURN v_result;
  END IF;

  IF p_short_or_full_id !~* '^[a-f0-9]{4,8}$' THEN
    RETURN NULL;
  END IF;

  SELECT array_agg(match.id)
  INTO v_matches
  FROM (
    SELECT pa.id
    FROM public.payroll_adjustments pa
    WHERE pa.user_id = v_user_id
      AND pa.deleted_at IS NULL
      AND pa.id::text LIKE lower(p_short_or_full_id) || '%'
    ORDER BY pa.id
    LIMIT 2
  ) AS match;

  IF coalesce(array_length(v_matches, 1), 0) = 1 THEN
    RETURN v_matches[1];
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_payroll_adjustment_id(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_payroll_adjustment_id(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_payroll_adjustment_id(text) TO authenticated;
