-- Capture linked definitions that predate the active migration history.
-- This is intentionally a forward-only, schema-equivalent reconciliation:
-- CREATE OR REPLACE preserves existing objects while making clean-room history
-- explicit. Privileges and comments are replayed from the read-only linked dump.

CREATE OR REPLACE FUNCTION "internal"."claim_outbox_notifications"("batch_size" integer DEFAULT 50) RETURNS SETOF "internal"."notifications_outbox"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'internal', 'pg_temp'
    AS $$
BEGIN
  -- Reset stale claims (stuck > 15 minutes) with bounded retries
  UPDATE notifications_outbox
  SET
    status = CASE
      WHEN attempts >= 10 THEN 'failed'  -- Max 10 attempts, then permanent failure
      ELSE 'pending'
    END,
    claimed_at = NULL,
    attempts = attempts + 1,
    error_message = CASE
      WHEN attempts >= 10 THEN 'Max retry attempts exceeded'
      ELSE error_message
    END
  WHERE status = 'sending'
    AND claimed_at < now() - INTERVAL '15 minutes';

  -- Claim and return batch (only pending with < 10 attempts)
  RETURN QUERY
  UPDATE notifications_outbox
  SET status = 'sending', claimed_at = now()
  WHERE id IN (
    SELECT id FROM notifications_outbox
    WHERE status = 'pending'
      AND due_at <= now()
      AND attempts < 10
    ORDER BY due_at
    LIMIT batch_size
    FOR UPDATE SKIP LOCKED
  )
  RETURNING *;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."admin_count_target_users_active"() RETURNS bigint
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
  SELECT COUNT(DISTINCT pd.user_id)
  FROM internal.push_devices pd
  INNER JOIN user_settings us ON us.user_id = pd.user_id
  WHERE us.last_active >= NOW() - INTERVAL '7 days';
$$;

CREATE OR REPLACE FUNCTION "public"."admin_count_target_users_all"("exclude_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS bigint
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
  SELECT COUNT(DISTINCT pd.user_id)
  FROM internal.push_devices pd
  WHERE (exclude_user_id IS NULL OR pd.user_id != exclude_user_id);
$$;

CREATE OR REPLACE FUNCTION "public"."admin_count_target_users_pro"() RETURNS bigint
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
  SELECT COUNT(DISTINCT pd.user_id)
  FROM internal.push_devices pd
  INNER JOIN subscriptions s ON s.user_id = pd.user_id
  WHERE s.status IN ('active', 'trialing');
$$;

CREATE OR REPLACE FUNCTION "public"."admin_get_audit_log"("p_limit" integer DEFAULT 50, "p_action_filter" "text" DEFAULT NULL::"text", "p_target_filter" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("id" "uuid", "admin_id" "uuid", "admin_email" "text", "action" "text", "target_user_id" "uuid", "target_email" "text", "metadata" "jsonb", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'internal'
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    a.id,
    a.admin_id,
    a.admin_email,
    a.action,
    a.target_user_id,
    a.target_email,
    a.metadata,
    a.created_at
  FROM internal.admin_audit_log a
  WHERE
    (p_action_filter IS NULL OR a.action = p_action_filter)
    AND (p_target_filter IS NULL OR a.target_user_id = p_target_filter)
  ORDER BY a.created_at DESC
  LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."admin_get_push_device_users"() RETURNS TABLE("user_id" "uuid")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'internal'
    AS $$
  SELECT pd.user_id
  FROM internal.push_devices pd
  GROUP BY pd.user_id
  ORDER BY MAX(pd.last_seen_at) DESC;
$$;

CREATE OR REPLACE FUNCTION "public"."admin_get_subscribers"() RETURNS TABLE("user_id" "uuid", "subscription_id" "uuid", "provider" "text", "product_id" "text", "price_id" "text", "status" "text", "current_period_end" timestamp with time zone, "is_grandfathered" boolean)
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    sub.user_id,
    sub.subscription_id,
    sub.provider,
    sub.product_id,
    sub.price_id,
    sub.status,
    sub.current_period_end,
    sub.is_grandfathered
  FROM (
    SELECT DISTINCT ON (COALESCE(s.user_id, p.id))
      COALESCE(s.user_id, p.id) as user_id,
      s.id as subscription_id,
      s.provider,
      s.product_id,
      s.price_id,
      s.status,
      s.current_period_end,
      COALESCE(p.before_paywall, false) as is_grandfathered
    FROM profiles p
    FULL OUTER JOIN subscriptions s ON p.id = s.user_id
    WHERE
      -- Has active subscription
      (
        s.status IN ('active', 'trialing', 'grace')
        AND (s.current_period_end IS NULL OR s.current_period_end > now())
      )
      -- OR is grandfathered
      OR p.before_paywall = true
    ORDER BY COALESCE(s.user_id, p.id), COALESCE(s.current_period_end, '2099-12-31'::timestamptz) DESC
  ) sub
  ORDER BY COALESCE(sub.current_period_end, '2099-12-31'::timestamptz) DESC;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."admin_get_target_users_active"() RETURNS TABLE("user_id" "uuid")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
  SELECT DISTINCT pd.user_id
  FROM internal.push_devices pd
  INNER JOIN user_settings us ON us.user_id = pd.user_id
  WHERE us.last_active >= NOW() - INTERVAL '7 days';
$$;

CREATE OR REPLACE FUNCTION "public"."admin_get_target_users_all"("exclude_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("user_id" "uuid")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
  SELECT DISTINCT pd.user_id
  FROM internal.push_devices pd
  WHERE (exclude_user_id IS NULL OR pd.user_id != exclude_user_id);
$$;

CREATE OR REPLACE FUNCTION "public"."admin_get_target_users_pro"() RETURNS TABLE("user_id" "uuid")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
  SELECT DISTINCT pd.user_id
  FROM internal.push_devices pd
  INNER JOIN subscriptions s ON s.user_id = pd.user_id
  WHERE s.status IN ('active', 'trialing');
$$;

CREATE OR REPLACE FUNCTION "public"."admin_get_user_locales"("user_ids" "uuid"[]) RETURNS TABLE("user_id" "uuid", "locale" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
  SELECT
    u.id AS user_id,
    COALESCE(u.raw_user_meta_data->>'locale', 'en') AS locale
  FROM auth.users u
  WHERE u.id = ANY(user_ids);
$$;

CREATE OR REPLACE FUNCTION "public"."check_impersonation_rate_limit"("p_admin_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
DECLARE
  attempt_count int;
BEGIN
  SELECT COUNT(*) INTO attempt_count
  FROM internal.impersonation_rate_limits
  WHERE admin_user_id = p_admin_user_id
    AND attempted_at > (now() - interval '1 hour');
  RETURN attempt_count < 10;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."check_mfa_aal"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  SELECT
    CASE
      -- If user is being impersonated, allow access (admin has already verified MFA)
      WHEN public.is_impersonation_session() THEN
        true
      -- If user has MFA factors, require AAL2
      WHEN public.user_has_verified_mfa_factors() THEN
        (auth.jwt()->>'aal') = 'aal2'
      -- Otherwise, allow access
      ELSE
        true
    END
$$;

CREATE OR REPLACE FUNCTION "public"."create_impersonation_session"("p_admin_user_id" "uuid", "p_target_user_id" "uuid", "p_admin_refresh_token_enc" "text" DEFAULT ''::"text", "p_reason" "text" DEFAULT NULL::"text", "p_admin_ip" "text" DEFAULT NULL::"text", "p_admin_user_agent" "text" DEFAULT NULL::"text", "p_admin_email" "text" DEFAULT NULL::"text", "p_target_email" "text" DEFAULT NULL::"text") RETURNS TABLE("session_id" "uuid", "expires_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
DECLARE
  v_session_id uuid;
  v_expires_at timestamptz;
BEGIN
  -- Calculate expiration (1 hour from now)
  v_expires_at := now() + interval '1 hour';

  -- Create the session (no is_active column - use ended_at IS NULL to check active)
  INSERT INTO internal.impersonation_sessions (
    admin_user_id,
    target_user_id,
    reason,
    admin_refresh_token_enc,
    expires_at,
    admin_ip,
    admin_user_agent,
    enc_kid,
    enc_alg,
    enc_format_ver
  ) VALUES (
    p_admin_user_id,
    p_target_user_id,
    COALESCE(p_reason, 'Admin impersonation'),
    COALESCE(p_admin_refresh_token_enc, ''),
    v_expires_at,
    p_admin_ip,
    p_admin_user_agent,
    'v1',
    'aes-256-gcm',
    1
  )
  RETURNING id INTO v_session_id;

  -- Create audit log entry
  INSERT INTO internal.impersonation_audit_log (
    session_id,
    admin_user_id,
    target_user_id,
    action,
    reason,
    admin_ip,
    admin_user_agent,
    metadata
  ) VALUES (
    v_session_id,
    p_admin_user_id,
    p_target_user_id,
    'start',
    p_reason,
    p_admin_ip,
    p_admin_user_agent,
    jsonb_build_object(
      'admin_email', p_admin_email,
      'target_email', p_target_email
    )
  );

  -- Record rate limit attempt
  INSERT INTO internal.impersonation_rate_limits (admin_user_id)
  VALUES (p_admin_user_id);

  -- Return both session ID and expires_at
  RETURN QUERY SELECT v_session_id, v_expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."end_impersonation_session"("p_session_id" "uuid", "p_admin_ip" "text" DEFAULT NULL::"text", "p_admin_user_agent" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
DECLARE
  v_session internal.impersonation_sessions%ROWTYPE;
BEGIN
  -- Get the session
  SELECT * INTO v_session
  FROM internal.impersonation_sessions
  WHERE id = p_session_id;

  IF v_session.id IS NULL THEN
    RETURN false;
  END IF;

  -- Mark session as ended (no is_active column, just set ended_at)
  UPDATE internal.impersonation_sessions
  SET ended_at = now()
  WHERE id = p_session_id
    AND ended_at IS NULL;

  -- Create audit log entry
  INSERT INTO internal.impersonation_audit_log (
    session_id,
    admin_user_id,
    target_user_id,
    action,
    admin_ip,
    admin_user_agent
  ) VALUES (
    p_session_id,
    v_session.admin_user_id,
    v_session.target_user_id,
    'stop',
    p_admin_ip,
    p_admin_user_agent
  );

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."find_user_by_email"("search_email" "text") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  SELECT id FROM auth.users 
  WHERE lower(email) = lower(search_email)
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION "public"."find_user_by_phone"("search_phone" "text") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  SELECT id FROM auth.users 
  WHERE phone = search_phone
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION "public"."get_active_impersonation_for_admin"("p_admin_user_id" "uuid") RETURNS TABLE("id" "uuid", "admin_user_id" "uuid", "target_user_id" "uuid", "admin_refresh_token_enc" "text", "expires_at" timestamp with time zone, "ended_at" timestamp with time zone, "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.id,
    s.admin_user_id,
    s.target_user_id,
    s.admin_refresh_token_enc,
    s.expires_at,
    s.ended_at,
    s.created_at
  FROM internal.impersonation_sessions s
  WHERE s.admin_user_id = p_admin_user_id
    AND s.ended_at IS NULL
  ORDER BY s.created_at DESC
  LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."get_admin_user_ids"() RETURNS SETOF "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth', 'pg_temp'
    AS $$
  SELECT id FROM auth.users
  WHERE raw_app_meta_data->>'role' = 'admin'
    AND deleted_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION "public"."get_impersonation_session"("p_session_id" "uuid") RETURNS TABLE("id" "uuid", "admin_user_id" "uuid", "target_user_id" "uuid", "admin_refresh_token_enc" "text", "expires_at" timestamp with time zone, "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.id,
    s.admin_user_id,
    s.target_user_id,
    s.admin_refresh_token_enc,
    s.expires_at,
    s.created_at
  FROM internal.impersonation_sessions s
  WHERE s.id = p_session_id
    AND s.ended_at IS NULL
    AND s.expires_at > now();
END;
$$;

CREATE OR REPLACE FUNCTION "public"."get_impersonation_session_full"("p_session_id" "uuid") RETURNS TABLE("id" "uuid", "admin_user_id" "uuid", "target_user_id" "uuid", "reason" "text", "admin_refresh_token_enc" "text", "expires_at" timestamp with time zone, "ended_at" timestamp with time zone, "ended_by_admin_user_id" "uuid", "admin_ip" "text", "admin_user_agent" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.id,
    s.admin_user_id,
    s.target_user_id,
    s.reason,
    s.admin_refresh_token_enc,
    s.expires_at,
    s.ended_at,
    s.ended_by_admin_user_id,
    s.admin_ip,
    s.admin_user_agent,
    s.created_at
  FROM internal.impersonation_sessions s
  WHERE s.id = p_session_id;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."get_my_entitlement"() RETURNS TABLE("user_id" "uuid", "tier" "text", "is_entitled" boolean, "is_grandfathered" boolean, "has_active_subscription" boolean, "active_provider" "text", "active_product_id" "text", "subscription_ends_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  SELECT
    ue.user_id,
    ue.tier,
    ue.is_entitled,
    ue.is_grandfathered,
    ue.has_active_subscription,
    ue.active_provider,
    ue.active_product_id,
    ue.subscription_ends_at
  FROM public.user_entitlements ue
  WHERE ue.user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION "public"."get_tariff_rate"("level" smallint) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF level = 0 OR level IS NULL THEN
    RETURN NULL; -- 0 => use custom wage
  END IF;
  RETURN CASE level
    WHEN -1 THEN 129.91
    WHEN -2 THEN 132.90
    WHEN 1 THEN 188.58
    WHEN 2 THEN 200.32
    WHEN 3 THEN 208.70
    WHEN 4 THEN 222.58
    WHEN 5 THEN 238.10
    WHEN 6 THEN 256.14
    ELSE NULL
  END;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."get_tariff_types"() RETURNS TABLE("id" "text", "display_name" "text", "description" "text", "country" "text", "is_default" boolean)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  SELECT id, display_name, description, country, is_default
  FROM internal.tariff_types
  ORDER BY is_default DESC, display_name;
$$;

CREATE OR REPLACE FUNCTION "public"."get_users_by_ids"("user_ids" "uuid"[]) RETURNS TABLE("id" "uuid", "email" "text", "phone" "text", "first_name" "text", "oauth_avatar_url" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  SELECT
    u.id,
    u.email,
    u.phone,
    COALESCE(
      u.raw_user_meta_data->>'full_name',
      u.raw_user_meta_data->>'name'
    ) as first_name,
    u.raw_user_meta_data->>'avatar_url' as oauth_avatar_url
  FROM auth.users u
  WHERE u.id = ANY(user_ids);
$$;

CREATE OR REPLACE FUNCTION "public"."insert_impersonation_audit_log"("p_session_id" "uuid", "p_admin_user_id" "uuid", "p_target_user_id" "uuid", "p_action" "text", "p_reason" "text" DEFAULT NULL::"text", "p_admin_ip" "text" DEFAULT NULL::"text", "p_admin_user_agent" "text" DEFAULT NULL::"text", "p_metadata" "jsonb" DEFAULT NULL::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
DECLARE
  v_log_id uuid;
BEGIN
  INSERT INTO internal.impersonation_audit_log (
    session_id,
    admin_user_id,
    target_user_id,
    action,
    reason,
    admin_ip,
    admin_user_agent,
    metadata
  ) VALUES (
    p_session_id,
    p_admin_user_id,
    p_target_user_id,
    p_action,
    p_reason,
    p_admin_ip,
    p_admin_user_agent,
    p_metadata
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."is_impersonation_session"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM internal.impersonation_sessions
    WHERE target_user_id = auth.uid()
      AND ended_at IS NULL
      AND expires_at > now()
  );
$$;

CREATE OR REPLACE FUNCTION "public"."is_superadmin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
  SELECT COALESCE(
    auth.uid() = '032d8c2a-9af6-4777-99f0-24e2c4058bf3'::uuid,
    false
  );
$$;

CREATE OR REPLACE FUNCTION "public"."is_user_being_impersonated"("p_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM internal.impersonation_sessions
    WHERE target_user_id = p_user_id
      AND ended_at IS NULL
      AND expires_at > now()
  );
END;
$$;

CREATE OR REPLACE FUNCTION "public"."jsonb_has_content"("val" "jsonb") RETURNS boolean
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT CASE
    WHEN val IS NULL THEN false
    WHEN jsonb_typeof(val) = 'array' THEN jsonb_array_length(val) > 0
    WHEN jsonb_typeof(val) = 'object' THEN val <> '{}'::jsonb
    ELSE true
  END;
$$;

CREATE OR REPLACE FUNCTION "public"."mark_impersonation_session_ended"("p_session_id" "uuid", "p_ended_by_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
DECLARE
  v_row_count integer;
BEGIN
  UPDATE internal.impersonation_sessions
  SET
    ended_at = now(),
    ended_by_admin_user_id = p_ended_by_user_id
  WHERE id = p_session_id
    AND ended_at IS NULL;

  GET DIAGNOSTICS v_row_count = ROW_COUNT;
  RETURN v_row_count > 0;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."queue_feedback_responded_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal', 'auth', 'pg_temp'
    AS $$
DECLARE
  v_user_locale TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  -- Only trigger when response is FIRST added (not on edits)
  IF OLD.response IS NULL AND NEW.response IS NOT NULL THEN
    -- Get user's locale preference
    SELECT COALESCE(raw_user_meta_data->>'locale', 'en')
    INTO v_user_locale
    FROM auth.users
    WHERE id = NEW.user_id;

    -- Build localized message
    IF v_user_locale IN ('no', 'nb', 'nn') THEN
      v_title := 'Svar på tilbakemeldingen din';
      v_body := LEFT(NEW.response, 150);
    ELSE
      v_title := 'Response to your feedback';
      v_body := LEFT(NEW.response, 150);
    END IF;

    -- Insert notification to outbox (the working path)
    INSERT INTO internal.notifications_outbox (
      owner_id,
      recipient_id,
      notification_type,
      due_at,
      title,
      body,
      data_payload,
      idempotency_key
    ) VALUES (
      NEW.responded_by,
      NEW.user_id,
      'feedback_responded',
      now(),
      v_title,
      v_body,
      jsonb_build_object(
        'type', 'feedback_responded',
        'feedback_id', NEW.id,
        'response_preview', LEFT(NEW.response, 150)
      ),
      'feedback_responded:' || NEW.id  -- Stable key, one notification per feedback
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."queue_feedback_submitted_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal', 'auth', 'pg_temp'
    AS $$
DECLARE
  v_user_name text;
  v_admin_id uuid;
BEGIN
  -- Get the submitter's name
  SELECT COALESCE(raw_user_meta_data->>'full_name', NEW.user_email)
  INTO v_user_name
  FROM auth.users
  WHERE id = NEW.user_id;

  -- Insert notification for each admin directly into notifications_outbox
  INSERT INTO internal.notifications_outbox (
    owner_id,
    recipient_id,
    notification_type,
    title,
    body,
    data_payload,
    idempotency_key,
    due_at,
    status
  )
  SELECT
    NEW.user_id,
    u.id,
    'feedback_submitted',
    'Ny tilbakemelding',
    v_user_name || ': ' || LEFT(NEW.message, 100) || CASE WHEN LENGTH(NEW.message) > 100 THEN '...' ELSE '' END,
    jsonb_build_object(
      'type', 'feedback_submitted',
      'feedback_id', NEW.id,
      'user_name', v_user_name,
      'user_email', NEW.user_email
    ),
    'feedback:' || NEW.id || ':' || u.id,
    NOW(),
    'pending'
  FROM auth.users u
  WHERE (u.raw_app_meta_data->>'role') = 'admin'
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."queue_share_started_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal', 'pg_temp'
    AS $$
DECLARE
  v_sharer_name TEXT;
  v_viewer_locale TEXT;
  v_title TEXT;
  v_body TEXT;
  v_viewer_prefs RECORD;
BEGIN
  -- Check viewer's notification preferences first (before doing more work)
  SELECT shared_shifts_enabled
  INTO v_viewer_prefs
  FROM notification_preferences
  WHERE user_id = NEW.viewer_id;

  -- Skip if viewer has shared_shifts_enabled = false
  IF COALESCE(v_viewer_prefs.shared_shifts_enabled, true) = false THEN
    RETURN NEW;
  END IF;

  -- Get the sharer's display name
  SELECT COALESCE(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', email, 'Someone')
  INTO v_sharer_name
  FROM auth.users
  WHERE id = NEW.owner_id;

  IF v_sharer_name IS NULL THEN
    v_sharer_name := 'Someone';
  END IF;

  -- Get viewer's locale preference
  SELECT COALESCE(raw_user_meta_data->>'locale', 'en')
  INTO v_viewer_locale
  FROM auth.users
  WHERE id = NEW.viewer_id;

  -- Build localized message
  IF v_viewer_locale IN ('no', 'nb', 'nn') THEN
    v_title := v_sharer_name || ' deler vakter med deg';
    v_body := 'Trykk for å se ' || v_sharer_name || ' sine vakter';
  ELSE
    v_title := v_sharer_name || ' is sharing shifts with you';
    v_body := 'Tap to see ' || v_sharer_name || '''s shifts';
  END IF;

  -- Insert notification to outbox (the working path)
  INSERT INTO internal.notifications_outbox (
    owner_id,
    recipient_id,
    notification_type,
    due_at,
    title,
    body,
    data_payload,
    idempotency_key
  )
  VALUES (
    NEW.owner_id,
    NEW.viewer_id,
    'share_started',
    now(),
    v_title,
    v_body,
    jsonb_build_object(
      'type', 'share_started',
      'owner_id', NEW.owner_id,
      'owner_name', v_sharer_name
    ),
    'share_started:' || NEW.owner_id || ':' || NEW.viewer_id
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."record_impersonation_attempt"("p_admin_user_id" "uuid", "p_success" boolean DEFAULT false) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'internal'
    AS $$
BEGIN
  INSERT INTO internal.impersonation_rate_limits (admin_user_id, success)
  VALUES (p_admin_user_id, p_success);

  DELETE FROM internal.impersonation_rate_limits
  WHERE attempted_at < (now() - interval '24 hours');
END;
$$;

CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."set_any_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF to_jsonb(NEW) ? 'updated_at' THEN
    NEW.updated_at = now();
  ELSIF to_jsonb(NEW) ? '_updated_at' THEN
    NEW._updated_at = now();
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."set_updated_at_and_revision"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
    NEW.updated_at = now();
    NEW.revision = OLD.revision + 1;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."set_updated_at_metadata"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."set_wage_snapshots_deleted_at_from_job"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  -- Only act when deleted_at changes from NULL to a value
  IF TG_OP = 'UPDATE' AND OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    UPDATE public.wage_snapshots ws
    SET deleted_at = NEW.deleted_at,
        updated_at = NOW()
    WHERE ws.job_id = NEW.id
      AND (ws.deleted_at IS DISTINCT FROM NEW.deleted_at);
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."try_parse_time"("val" "text") RETURNS time without time zone
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF val IS NULL OR btrim(val) = '' THEN
    RETURN NULL;
  END IF;

  BEGIN
    RETURN val::time;
  EXCEPTION WHEN others THEN
    RETURN NULL;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."update_notification_preferences_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."update_push_devices_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'internal'
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."user_has_verified_mfa_factors"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM auth.mfa_factors
    WHERE user_id = auth.uid()
      AND status = 'verified'
  )
$$;

CREATE OR REPLACE VIEW "public"."user_entitlements" AS
 SELECT "u"."id" AS "user_id",
    COALESCE("p"."before_paywall", false) AS "is_grandfathered",
    ("s"."user_id" IS NOT NULL) AS "has_active_subscription",
    (COALESCE("p"."before_paywall", false) OR ("s"."user_id" IS NOT NULL)) AS "is_entitled",
    "s"."provider" AS "active_provider",
    "s"."product_id" AS "active_product_id",
    "s"."current_period_end" AS "subscription_ends_at",
        CASE
            WHEN (COALESCE("p"."before_paywall", false) AND ("s"."user_id" IS NULL)) THEN 'pro'::"text"
            WHEN ("s"."product_id" = ANY (ARRAY['max_monthly'::"text", 'max_yearly'::"text", 'no.tidex.max'::"text", 'no.tidex.max.year'::"text"])) THEN 'max'::"text"
            WHEN ("s"."product_id" = ANY (ARRAY['pro_monthly'::"text", 'pro_yearly'::"text", 'no.tidex.pro'::"text", 'no.tidex.pro.year'::"text"])) THEN 'pro'::"text"
            WHEN COALESCE("p"."before_paywall", false) THEN 'pro'::"text"
            ELSE 'free'::"text"
        END AS "tier"
   FROM (("auth"."users" "u"
     LEFT JOIN "public"."profiles" "p" ON (("p"."id" = "u"."id")))
     LEFT JOIN LATERAL ( SELECT "s_1"."user_id",
            "s_1"."provider",
            "s_1"."product_id",
            "s_1"."current_period_end"
           FROM "public"."subscriptions" "s_1"
          WHERE (("s_1"."user_id" = "u"."id") AND ("s_1"."status" = ANY (ARRAY['active'::"text", 'trialing'::"text", 'grace'::"text"])) AND (("s_1"."current_period_end" IS NULL) OR ("s_1"."current_period_end" > "now"())))
          ORDER BY "s_1"."current_period_end" DESC NULLS LAST
         LIMIT 1) "s" ON (true));

CREATE OR REPLACE VIEW "public"."user_shift_counts" WITH ("security_invoker"='on') AS
 SELECT "u"."id" AS "user_id",
    COALESCE(("u"."raw_user_meta_data" ->> 'name'::"text"), ("u"."raw_user_meta_data" ->> 'full_name'::"text")) AS "name",
    "u"."email",
    "u"."created_at",
    COALESCE("us"."cnt", (0)::bigint) AS "user_shifts_count",
    COALESCE("rs"."cnt", (0)::bigint) AS "recurring_shifts_count",
    (COALESCE("us"."cnt", (0)::bigint) + COALESCE("rs"."cnt", (0)::bigint)) AS "total_count"
   FROM (("auth"."users" "u"
     LEFT JOIN ( SELECT "user_shifts"."user_id",
            "count"(*) AS "cnt"
           FROM "public"."user_shifts"
          GROUP BY "user_shifts"."user_id") "us" ON (("us"."user_id" = "u"."id")))
     LEFT JOIN ( SELECT "recurring_shifts"."user_id",
            "count"(*) AS "cnt"
           FROM "public"."recurring_shifts"
          GROUP BY "recurring_shifts"."user_id") "rs" ON (("rs"."user_id" = "u"."id")));

COMMENT ON FUNCTION "public"."admin_get_audit_log"("p_limit" integer, "p_action_filter" "text", "p_target_filter" "uuid") IS 'Returns recent audit log entries with optional action and target filters. Uses SECURITY INVOKER with RLS.';

COMMENT ON FUNCTION "public"."admin_get_subscribers"() IS 'Returns users with active subscriptions or grandfathered status. Uses DISTINCT ON to avoid ORDER BY errors.';

COMMENT ON FUNCTION "public"."create_impersonation_session"("p_admin_user_id" "uuid", "p_target_user_id" "uuid", "p_admin_refresh_token_enc" "text", "p_reason" "text", "p_admin_ip" "text", "p_admin_user_agent" "text", "p_admin_email" "text", "p_target_email" "text") IS 'Creates an impersonation session with audit logging. Returns session_id and expires_at. Used by Edge Function.';

COMMENT ON FUNCTION "public"."end_impersonation_session"("p_session_id" "uuid", "p_admin_ip" "text", "p_admin_user_agent" "text") IS 'Ends an impersonation session with audit logging. Used by Edge Function.';

COMMENT ON FUNCTION "public"."get_my_entitlement"() IS 'Returns entitlement status for the authenticated user only. Uses auth.uid() server-side for security - cannot be spoofed by client.';

COMMENT ON FUNCTION "public"."get_tariff_types"() IS 'Get all available tariff types for wage selection';

COMMENT ON FUNCTION "public"."set_updated_at_and_revision"() IS 'Unified trigger function for offline sync. Sets updated_at to current timestamp and increments revision on each update.';

COMMENT ON VIEW "public"."user_entitlements" IS 'Unified view of user subscription entitlements. Used by RLS policies, admin queries, iOS app, and debugging. Product_id is single source of truth for tier.';

REVOKE ALL ON FUNCTION "internal"."claim_outbox_notifications"("batch_size" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "internal"."claim_outbox_notifications"("batch_size" integer) TO "service_role";

REVOKE ALL ON FUNCTION "public"."admin_count_target_users_active"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."admin_count_target_users_active"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."admin_count_target_users_all"("exclude_user_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."admin_count_target_users_all"("exclude_user_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."admin_count_target_users_pro"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."admin_count_target_users_pro"() TO "service_role";

GRANT ALL ON FUNCTION "public"."admin_get_audit_log"("p_limit" integer, "p_action_filter" "text", "p_target_filter" "uuid") TO "anon";

GRANT ALL ON FUNCTION "public"."admin_get_audit_log"("p_limit" integer, "p_action_filter" "text", "p_target_filter" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."admin_get_audit_log"("p_limit" integer, "p_action_filter" "text", "p_target_filter" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."admin_get_push_device_users"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."admin_get_push_device_users"() TO "service_role";

GRANT ALL ON FUNCTION "public"."admin_get_subscribers"() TO "anon";

GRANT ALL ON FUNCTION "public"."admin_get_subscribers"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."admin_get_subscribers"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."admin_get_target_users_active"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."admin_get_target_users_active"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."admin_get_target_users_all"("exclude_user_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."admin_get_target_users_all"("exclude_user_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."admin_get_target_users_pro"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."admin_get_target_users_pro"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."admin_get_user_locales"("user_ids" "uuid"[]) FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."admin_get_user_locales"("user_ids" "uuid"[]) TO "service_role";

REVOKE ALL ON FUNCTION "public"."check_impersonation_rate_limit"("p_admin_user_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."check_impersonation_rate_limit"("p_admin_user_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."check_mfa_aal"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."check_mfa_aal"() TO "service_role";

GRANT ALL ON FUNCTION "public"."check_mfa_aal"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."create_impersonation_session"("p_admin_user_id" "uuid", "p_target_user_id" "uuid", "p_admin_refresh_token_enc" "text", "p_reason" "text", "p_admin_ip" "text", "p_admin_user_agent" "text", "p_admin_email" "text", "p_target_email" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."create_impersonation_session"("p_admin_user_id" "uuid", "p_target_user_id" "uuid", "p_admin_refresh_token_enc" "text", "p_reason" "text", "p_admin_ip" "text", "p_admin_user_agent" "text", "p_admin_email" "text", "p_target_email" "text") TO "service_role";

REVOKE ALL ON FUNCTION "public"."end_impersonation_session"("p_session_id" "uuid", "p_admin_ip" "text", "p_admin_user_agent" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."end_impersonation_session"("p_session_id" "uuid", "p_admin_ip" "text", "p_admin_user_agent" "text") TO "service_role";

REVOKE ALL ON FUNCTION "public"."find_user_by_email"("search_email" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."find_user_by_email"("search_email" "text") TO "service_role";

REVOKE ALL ON FUNCTION "public"."find_user_by_phone"("search_phone" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."find_user_by_phone"("search_phone" "text") TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_active_impersonation_for_admin"("p_admin_user_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."get_active_impersonation_for_admin"("p_admin_user_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_admin_user_ids"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."get_admin_user_ids"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_impersonation_session"("p_session_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."get_impersonation_session"("p_session_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_impersonation_session_full"("p_session_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."get_impersonation_session_full"("p_session_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_my_entitlement"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."get_my_entitlement"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."get_my_entitlement"() TO "service_role";

GRANT ALL ON FUNCTION "public"."get_tariff_rate"("level" smallint) TO "anon";

GRANT ALL ON FUNCTION "public"."get_tariff_rate"("level" smallint) TO "authenticated";

GRANT ALL ON FUNCTION "public"."get_tariff_rate"("level" smallint) TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_tariff_types"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."get_tariff_types"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."get_tariff_types"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_users_by_ids"("user_ids" "uuid"[]) FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."get_users_by_ids"("user_ids" "uuid"[]) TO "service_role";

REVOKE ALL ON FUNCTION "public"."insert_impersonation_audit_log"("p_session_id" "uuid", "p_admin_user_id" "uuid", "p_target_user_id" "uuid", "p_action" "text", "p_reason" "text", "p_admin_ip" "text", "p_admin_user_agent" "text", "p_metadata" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."insert_impersonation_audit_log"("p_session_id" "uuid", "p_admin_user_id" "uuid", "p_target_user_id" "uuid", "p_action" "text", "p_reason" "text", "p_admin_ip" "text", "p_admin_user_agent" "text", "p_metadata" "jsonb") TO "service_role";

REVOKE ALL ON FUNCTION "public"."is_impersonation_session"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."is_impersonation_session"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."is_superadmin"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."is_superadmin"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."is_user_being_impersonated"("p_user_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."is_user_being_impersonated"("p_user_id" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."jsonb_has_content"("val" "jsonb") TO "anon";

GRANT ALL ON FUNCTION "public"."jsonb_has_content"("val" "jsonb") TO "authenticated";

GRANT ALL ON FUNCTION "public"."jsonb_has_content"("val" "jsonb") TO "service_role";

REVOKE ALL ON FUNCTION "public"."mark_impersonation_session_ended"("p_session_id" "uuid", "p_ended_by_user_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."mark_impersonation_session_ended"("p_session_id" "uuid", "p_ended_by_user_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."queue_feedback_responded_notification"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."queue_feedback_responded_notification"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."queue_feedback_submitted_notification"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."queue_feedback_submitted_notification"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."queue_share_started_notification"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."queue_share_started_notification"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."record_impersonation_attempt"("p_admin_user_id" "uuid", "p_success" boolean) FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."record_impersonation_attempt"("p_admin_user_id" "uuid", "p_success" boolean) TO "service_role";

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";

GRANT ALL ON FUNCTION "public"."set_any_updated_at"() TO "anon";

GRANT ALL ON FUNCTION "public"."set_any_updated_at"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."set_any_updated_at"() TO "service_role";

GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";

GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";

GRANT ALL ON FUNCTION "public"."set_updated_at_and_revision"() TO "anon";

GRANT ALL ON FUNCTION "public"."set_updated_at_and_revision"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."set_updated_at_and_revision"() TO "service_role";

GRANT ALL ON FUNCTION "public"."set_updated_at_metadata"() TO "anon";

GRANT ALL ON FUNCTION "public"."set_updated_at_metadata"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."set_updated_at_metadata"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."set_wage_snapshots_deleted_at_from_job"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."set_wage_snapshots_deleted_at_from_job"() TO "service_role";

GRANT ALL ON FUNCTION "public"."try_parse_time"("val" "text") TO "anon";

GRANT ALL ON FUNCTION "public"."try_parse_time"("val" "text") TO "authenticated";

GRANT ALL ON FUNCTION "public"."try_parse_time"("val" "text") TO "service_role";

GRANT ALL ON FUNCTION "public"."update_notification_preferences_updated_at"() TO "anon";

GRANT ALL ON FUNCTION "public"."update_notification_preferences_updated_at"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."update_notification_preferences_updated_at"() TO "service_role";

GRANT ALL ON FUNCTION "public"."update_push_devices_updated_at"() TO "anon";

GRANT ALL ON FUNCTION "public"."update_push_devices_updated_at"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."update_push_devices_updated_at"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."user_has_verified_mfa_factors"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."user_has_verified_mfa_factors"() TO "service_role";

REVOKE ALL ON TABLE "public"."user_entitlements" FROM PUBLIC;

REVOKE ALL ON TABLE "public"."user_entitlements" FROM "anon";

REVOKE ALL ON TABLE "public"."user_entitlements" FROM "authenticated";

GRANT ALL ON TABLE "public"."user_entitlements" TO "service_role";

GRANT ALL ON TABLE "public"."user_shift_counts" TO "anon";

GRANT ALL ON TABLE "public"."user_shift_counts" TO "authenticated";

GRANT ALL ON TABLE "public"."user_shift_counts" TO "service_role";
