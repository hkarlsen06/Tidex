-- Function: get_tariff_version_for_date
-- Description: Returns the tariff version that applies on a target date.

CREATE OR REPLACE FUNCTION public.get_tariff_version_for_date(
  p_tariff_type text,
  p_target_date date
)
RETURNS TABLE (
  id uuid,
  tariff_type_id text,
  effective_date date,
  name text,
  rates jsonb,
  supplements jsonb,
  overtime jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT id, tariff_type_id, effective_date, name, rates, supplements, overtime
  FROM internal.tariff_versions
  WHERE tariff_type_id = p_tariff_type
    AND effective_date <= p_target_date
  ORDER BY effective_date DESC
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.get_tariff_version_for_date(text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_tariff_version_for_date(text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_tariff_version_for_date(text, date) TO service_role;
