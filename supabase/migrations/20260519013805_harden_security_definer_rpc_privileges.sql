-- Revoke direct access to legacy admin helper RPCs that do not assert admin.
-- Current admin clients use the guarded *_api wrappers instead.
REVOKE EXECUTE ON FUNCTION public.admin_count_target_users_active() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_count_target_users_all(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_count_target_users_pro() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_get_broadcast_history(integer) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_get_target_users_active() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_get_target_users_all(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_get_target_users_pro() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_get_user_locales(uuid[]) FROM authenticated;

CREATE OR REPLACE FUNCTION public.get_user_entitlement_status(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'user_id', user_id,
    'is_entitled', is_entitled,
    'is_grandfathered', is_grandfathered,
    'has_active_subscription', has_active_subscription,
    'active_provider', active_provider,
    'active_product_id', active_product_id,
    'subscription_ends_at', subscription_ends_at
  )
  FROM public.user_entitlements
  WHERE user_id = p_user_id
    AND (
      p_user_id = auth.uid()
      OR auth.role() = 'service_role'
      OR public.is_admin()
    );
$function$;

CREATE OR REPLACE FUNCTION public.has_shift_storage_entitlement(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT COALESCE(
    (
      SELECT is_entitled
      FROM public.user_entitlements
      WHERE user_id = p_user_id
        AND (
          p_user_id = auth.uid()
          OR auth.role() = 'service_role'
          OR public.is_admin()
        )
    ),
    false
  );
$function$;

CREATE OR REPLACE FUNCTION public.user_has_any_shifts(u uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.user_shifts
    where user_id = u
      and (
        u = auth.uid()
        or auth.role() = 'service_role'
        or public.is_admin()
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.user_has_shift_in_month(u uuid, d date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.user_shifts
    where user_id = u
      and (
        u = auth.uid()
        or auth.role() = 'service_role'
        or public.is_admin()
      )
      and date_trunc('month', shift_date)::date = date_trunc('month', d)::date
  );
$function$;

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
  IF auth.uid() IS NULL OR p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

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

  SELECT COUNT(*) INTO current_token_count
  FROM internal.push_devices
  WHERE user_id = p_user_id;

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

REVOKE EXECUTE ON FUNCTION public.register_push_device(uuid, text, text, text, text, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.register_push_device(uuid, text, text, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.register_push_device(uuid, text, text, text, text, text) TO authenticated;

-- Wagey invocations now go through the authenticated Edge Function, which
-- validates the user token and calls this RPC with a service-role client.
REVOKE EXECUTE ON FUNCTION public.increment_wagey_bonus(uuid, integer) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.increment_wagey_invocation(uuid, text, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.increment_wagey_bonus(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.increment_wagey_invocation(uuid, text, integer) TO service_role;
