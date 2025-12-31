-- Function: set_updated_at_metadata
-- Description: Trigger function that sets updated_at for metadata tables
-- Used by: BEFORE UPDATE triggers on metadata tables

CREATE OR REPLACE FUNCTION public.set_updated_at_metadata()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;
