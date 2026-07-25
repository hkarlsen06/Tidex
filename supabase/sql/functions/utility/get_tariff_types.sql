-- Returns tariff types available for wage selection.
CREATE OR REPLACE FUNCTION public.get_tariff_types()
RETURNS TABLE(
  id text,
  display_name text,
  description text,
  country text,
  is_default boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT id, display_name, description, country, is_default
  FROM internal.tariff_types
  ORDER BY is_default DESC, display_name;
$function$;

COMMENT ON FUNCTION public.get_tariff_types()
  IS 'Get all available tariff types for wage selection';

REVOKE ALL ON FUNCTION public.get_tariff_types()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_tariff_types()
  TO authenticated, service_role;
