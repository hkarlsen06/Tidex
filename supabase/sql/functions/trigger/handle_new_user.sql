-- Function: handle_new_user
-- Description: Trigger function that creates a profile for new users
-- Used by: AFTER INSERT trigger on auth.users

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$function$;
