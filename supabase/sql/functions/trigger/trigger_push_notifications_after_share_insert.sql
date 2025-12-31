-- Function: trigger_push_notifications_after_share_insert
-- Description: Trigger function that calls send-push-notifications after share_started notification insert
-- Used by: AFTER INSERT trigger on shift_shares

CREATE OR REPLACE FUNCTION public.trigger_push_notifications_after_share_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  has_pending BOOLEAN;
  supabase_url TEXT;
  service_role_key TEXT;
BEGIN
  -- Check if there are any pending share_started notifications
  SELECT EXISTS (
    SELECT 1 FROM notification_queue
    WHERE type = 'share_started' AND status = 'pending'
  ) INTO has_pending;

  IF NOT has_pending THEN
    RETURN NULL;
  END IF;

  -- Get secrets from vault
  SELECT decrypted_secret INTO supabase_url
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_url';

  SELECT decrypted_secret INTO service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key';

  -- Call edge function to process notifications
  IF supabase_url IS NOT NULL AND service_role_key IS NOT NULL THEN
    PERFORM net.http_post(
      url := supabase_url || '/functions/v1/send-push-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key
      ),
      body := '{}'::jsonb
    );
  END IF;

  RETURN NULL;
END;
$function$;
