-- Function: is_admin
-- Description: Checks if the current user has admin role in app_metadata and
--              a session that completed MFA (aal2)
-- Used by: RLS policies and admin RPCs for admin-only features

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
