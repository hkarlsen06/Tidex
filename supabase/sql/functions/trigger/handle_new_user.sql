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

  INSERT INTO public.jobs (user_id, name, is_default, currency)
  VALUES (
    NEW.id,
    'Jobb',
    true,
    COALESCE(
      (
        SELECT us.currency
        FROM public.user_settings us
        WHERE us.user_id = NEW.id
        LIMIT 1
      ),
      'kr'
    )
  )
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$function$;
