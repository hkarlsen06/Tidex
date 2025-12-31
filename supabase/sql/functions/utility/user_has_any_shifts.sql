-- Function: user_has_any_shifts
-- Description: Checks if a user has any shifts
-- Used by: Various feature checks

CREATE OR REPLACE FUNCTION public.user_has_any_shifts(u uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.user_shifts where user_id = u);
$function$;
