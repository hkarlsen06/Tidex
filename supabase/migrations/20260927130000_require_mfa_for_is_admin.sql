-- Admin checks also require a session that completed MFA (aal2). Both admin
-- accounts have a verified factor. Service-role callers never reach this path:
-- the SQL functions that call is_admin() check auth.role() = 'service_role'
-- separately, and auth.uid() is NULL for them.
CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT COALESCE(
    (
      SELECT u.raw_app_meta_data ->> 'role' = 'admin'
        AND (auth.jwt() ->> 'aal') = 'aal2'
      FROM auth.users u
      WHERE u.id = auth.uid()
    ),
    false
  );
$function$;
