-- Unified trigger function for offline sync.
CREATE OR REPLACE FUNCTION public.set_updated_at_and_revision()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
    NEW.updated_at = now();
    NEW.revision = OLD.revision + 1;
    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.set_updated_at_and_revision()
  IS 'Unified trigger function for offline sync. Sets updated_at to current timestamp and increments revision on each update.';

GRANT EXECUTE ON FUNCTION public.set_updated_at_and_revision()
  TO PUBLIC, anon, authenticated, service_role;
