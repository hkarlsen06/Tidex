-- Function: internal.trigger_push_notifications_after_outbox_insert
-- Description: Trigger function that calls send-push-notifications after outbox inserts or delivery updates
-- Used by: AFTER INSERT / targeted UPDATE trigger on internal.notifications_outbox
-- Schema: internal (to match the trigger table)

CREATE OR REPLACE FUNCTION internal.trigger_push_notifications_after_outbox_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'net', 'pg_temp'
AS $function$
DECLARE
  supabase_url TEXT;
  service_key TEXT;
BEGIN
  -- Get secrets from vault
  SELECT decrypted_secret INTO supabase_url
  FROM vault.decrypted_secrets WHERE name = 'supabase_url';

  SELECT decrypted_secret INTO service_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  -- Only call if we have the required secrets
  IF supabase_url IS NOT NULL AND service_key IS NOT NULL THEN
    -- Use pg_net to call edge function asynchronously
    PERFORM net.http_post(
      url := supabase_url || '/functions/v1/send-push-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_key
      ),
      body := '{}'::jsonb
    );
  END IF;

  RETURN NULL;
END;
$function$;

-- Create the AFTER INSERT / targeted UPDATE trigger on notifications_outbox
DROP TRIGGER IF EXISTS trigger_send_push_after_insert ON internal.notifications_outbox;

CREATE TRIGGER trigger_send_push_after_insert
  AFTER INSERT OR UPDATE OF due_at, title, body, data_payload ON internal.notifications_outbox
  FOR EACH STATEMENT
  EXECUTE FUNCTION internal.trigger_push_notifications_after_outbox_insert();

-- Grant execute permission to service_role
GRANT EXECUTE ON FUNCTION internal.trigger_push_notifications_after_outbox_insert() TO service_role;
