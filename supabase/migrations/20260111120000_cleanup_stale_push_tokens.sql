-- Migration: Limit push tokens per user
--
-- Problem: FCM generates new tokens on reinstall/update, causing token accumulation.
-- Old tokens are accepted by FCM but fail to deliver, causing missed notifications.
--
-- Solution: Limit each user to max 3 tokens. When registering a new token,
-- delete the oldest ones if the user already has 3.

-- ==============================================================================
-- UPDATE REGISTER FUNCTION TO ENFORCE MAX 3 TOKENS PER USER
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.register_push_device(
  p_user_id uuid,
  p_fcm_token text,
  p_platform text,
  p_device_id text DEFAULT NULL,
  p_device_model text DEFAULT NULL,
  p_app_version text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  max_tokens_per_user CONSTANT int := 3;
  current_token_count int;
BEGIN
  -- Upsert the current token first
  INSERT INTO internal.push_devices (
    user_id,
    fcm_token,
    platform,
    device_id,
    device_model,
    app_version,
    last_seen_at
  ) VALUES (
    p_user_id,
    p_fcm_token,
    p_platform,
    p_device_id,
    p_device_model,
    p_app_version,
    now()
  )
  ON CONFLICT (fcm_token) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    platform = EXCLUDED.platform,
    device_id = EXCLUDED.device_id,
    device_model = EXCLUDED.device_model,
    app_version = EXCLUDED.app_version,
    last_seen_at = now();

  -- Count tokens for this user
  SELECT COUNT(*) INTO current_token_count
  FROM internal.push_devices
  WHERE user_id = p_user_id;

  -- If over limit, delete oldest tokens (keep only the newest 3)
  IF current_token_count > max_tokens_per_user THEN
    DELETE FROM internal.push_devices
    WHERE id IN (
      SELECT id
      FROM internal.push_devices
      WHERE user_id = p_user_id
      ORDER BY last_seen_at DESC
      OFFSET max_tokens_per_user
    );
  END IF;
END;
$function$;

-- ==============================================================================
-- DONE
-- ==============================================================================
