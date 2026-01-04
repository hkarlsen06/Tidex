-- Function: is_superadmin
-- Description: Checks if the current user is the superadmin (Hjalmar's account)
-- The superadmin is the only user who can grant/revoke admin privileges
-- Used by: RLS policies for superadmin-only features (admin management)

CREATE OR REPLACE FUNCTION public.is_superadmin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT COALESCE(
    auth.uid() = '032d8c2a-9af6-4777-99f0-24e2c4058bf3'::uuid,
    false
  );
$function$;
