-- Function: update_push_devices_updated_at
-- Description: Trigger function that sets updated_at for push_devices
-- Used by: BEFORE UPDATE trigger on push_devices

CREATE OR REPLACE FUNCTION public.update_push_devices_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;
