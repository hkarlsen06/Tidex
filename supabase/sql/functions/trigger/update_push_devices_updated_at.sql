-- Function: update_push_devices_updated_at
-- Description: Trigger function that sets updated_at for push_devices (now in internal schema)
-- Used by: BEFORE UPDATE trigger on internal.push_devices
-- Note: Function stays in public schema but operates on internal.push_devices table

CREATE OR REPLACE FUNCTION public.update_push_devices_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'internal'
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;
