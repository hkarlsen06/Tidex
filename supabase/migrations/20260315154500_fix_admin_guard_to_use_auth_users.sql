-- Fix admin authorization checks to read from auth.users instead of JWT claims.

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT COALESCE(
    (
      SELECT u.raw_app_meta_data ->> 'role' = 'admin'
      FROM auth.users u
      WHERE u.id = auth.uid()
    ),
    false
  );
$function$;
