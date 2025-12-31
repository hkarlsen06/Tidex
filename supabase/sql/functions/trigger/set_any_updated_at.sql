-- Function: set_any_updated_at
-- Description: Generic trigger function that sets updated_at or _updated_at column
-- Used by: BEFORE UPDATE triggers on various tables

CREATE OR REPLACE FUNCTION public.set_any_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF to_jsonb(NEW) ? 'updated_at' THEN
    NEW.updated_at = now();
  ELSIF to_jsonb(NEW) ? '_updated_at' THEN
    NEW._updated_at = now();
  END IF;

  RETURN NEW;
END;
$function$;
