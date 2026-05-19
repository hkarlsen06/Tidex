-- Function: user_has_shift_in_month
-- Description: Checks if a user has any shifts in a given month
-- Used by: Various feature checks

CREATE OR REPLACE FUNCTION public.user_has_shift_in_month(u uuid, d date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.user_shifts
    where user_id = u
      and (
        u = auth.uid()
        or auth.role() = 'service_role'
        or public.is_admin()
      )
      and date_trunc('month', shift_date)::date = date_trunc('month', d)::date
  );
$function$;

REVOKE EXECUTE ON FUNCTION public.user_has_shift_in_month(uuid, date) FROM authenticated;
