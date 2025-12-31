-- Function: update_notification_preferences_updated_at
-- Description: Trigger function that sets updated_at for notification_preferences
-- Used by: BEFORE UPDATE trigger on notification_preferences

CREATE OR REPLACE FUNCTION public.update_notification_preferences_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;
