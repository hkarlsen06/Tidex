-- Function: set_updated_at
-- Description: Simple trigger function that sets updated_at to now()
-- Used by: BEFORE UPDATE triggers on various tables

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;
