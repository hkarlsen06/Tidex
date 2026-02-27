-- Function: handle_new_user
-- Description: Trigger function that creates a profile + default job for new users
-- Used by: AFTER INSERT trigger on auth.users

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.profiles (id)
  VALUES (NEW.id)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.jobs (user_id, name, is_default)
  VALUES (NEW.id, 'Jobb', true)
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$function$;
