-- Function: get_tariff_versions
-- Description: Returns tariff versions for a tariff type, newest first.

CREATE OR REPLACE FUNCTION public.get_tariff_versions(
  p_tariff_type text DEFAULT 'hk_retail'::text
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
  ORDER BY effective_date DESC;
$function$;

REVOKE ALL ON FUNCTION public.get_tariff_versions(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_tariff_versions(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_tariff_versions(text) TO service_role;
