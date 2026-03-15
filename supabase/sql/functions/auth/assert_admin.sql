-- Function: assert_is_admin / assert_is_superadmin
-- Description: Raises when the current authenticated user is not authorized.

CREATE OR REPLACE FUNCTION public.assert_is_admin()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.assert_is_superadmin()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_superadmin() THEN
    RAISE EXCEPTION 'Superadmin access required';
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.assert_is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.assert_is_superadmin() TO authenticated;
