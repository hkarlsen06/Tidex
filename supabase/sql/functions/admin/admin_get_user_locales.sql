-- Function: admin_get_user_locales
-- Description: Returns user locales from auth.users for given user IDs
-- Used by: Admin broadcast notification localization

CREATE OR REPLACE FUNCTION public.admin_get_user_locales(user_ids uuid[])
 RETURNS TABLE(user_id uuid, locale text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT
    u.id AS user_id,
    COALESCE(u.raw_user_meta_data->>'locale', 'en') AS locale
  FROM auth.users u
  WHERE u.id = ANY(user_ids);
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_get_user_locales(uuid[]) FROM authenticated;
