-- Avoid treating every accelerated sandbox renewal as an introductory trial.

CREATE OR REPLACE FUNCTION internal.queue_subscription_trial_reminders(p_batch_size integer DEFAULT 500)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_trial_enabled boolean;
  v_trial_duration_days integer;
  v_reminder_days_before_end integer;
  v_reminder_interval interval;
  v_inserted_count integer := 0;
BEGIN
  SELECT
    pc.free_trial_enabled,
    pc.free_trial_duration_days,
    pc.free_trial_reminder_days_before_end
  INTO
    v_trial_enabled,
    v_trial_duration_days,
    v_reminder_days_before_end
  FROM internal.paywall_config pc
  WHERE pc.singleton = true;

  v_trial_enabled := COALESCE(v_trial_enabled, true);
  v_trial_duration_days := GREATEST(COALESCE(v_trial_duration_days, 14), 1);
  v_reminder_days_before_end := LEAST(
    GREATEST(COALESCE(v_reminder_days_before_end, 2), 1),
    v_trial_duration_days
  );

  IF NOT v_trial_enabled THEN
    RETURN 0;
  END IF;

  v_reminder_interval := v_reminder_days_before_end * interval '1 day';

  WITH trial_candidates AS (
    SELECT
      s.id AS subscription_id,
      s.user_id,
      s.status,
      s.current_period_start,
      s.current_period_end,
      COALESCE(NULLIF(au.raw_user_meta_data->>'locale', ''), 'en') AS locale,
      CASE
        WHEN s.raw_provider_payload #>> '{transactionInfo,offerType}' ~ '^[0-9]+$'
          THEN (s.raw_provider_payload #>> '{transactionInfo,offerType}')::integer
        ELSE NULL
      END AS apple_offer_type,
      (
        NULLIF(s.raw_provider_payload #>> '{transactionInfo,transactionId}', '') IS NOT NULL
        AND (s.raw_provider_payload #>> '{transactionInfo,transactionId}')
          = (s.raw_provider_payload #>> '{transactionInfo,originalTransactionId}')
      ) AS is_initial_apple_transaction
    FROM public.subscriptions s
    JOIN auth.users au
      ON au.id = s.user_id
    WHERE s.provider = 'apple'
      AND s.status IN ('active', 'trialing')
      AND s.product_id IN ('pro_monthly', 'pro_yearly', 'max_monthly', 'max_yearly', 'no.tidex.pro', 'no.tidex.pro.year', 'no.tidex.max', 'no.tidex.max.year')
      AND s.current_period_start IS NOT NULL
      AND s.current_period_end IS NOT NULL
      AND s.current_period_end > now()
    ORDER BY s.current_period_end
    LIMIT GREATEST(COALESCE(p_batch_size, 500), 1)
  ),
  filtered_trials AS (
    SELECT *
    FROM trial_candidates tc
    WHERE tc.status = 'trialing'
      OR tc.apple_offer_type = 1
      OR (
        tc.is_initial_apple_transaction
        AND tc.current_period_end <= tc.current_period_start + ((v_trial_duration_days + 1) * interval '1 day')
      )
  ),
  inserted AS (
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
    SELECT
      NULL,
      ft.user_id,
      'subscription_trial_reminder',
      GREATEST(now(), ft.current_period_end - v_reminder_interval),
      CASE
        WHEN ft.locale IN ('no', 'nb', 'nn') THEN 'Prøveperioden avsluttes snart'
        ELSE 'Your free trial ends soon'
      END,
      CASE
        WHEN ft.locale IN ('no', 'nb', 'nn') THEN
          'Tidex Pro fornyes om ' || v_reminder_days_before_end::text ||
          CASE WHEN v_reminder_days_before_end = 1 THEN ' dag. ' ELSE ' dager. ' END ||
          'Avslutt når som helst i App Store-innstillingene.'
        ELSE
          'Tidex Pro renews in ' || v_reminder_days_before_end::text ||
          CASE WHEN v_reminder_days_before_end = 1 THEN ' day. ' ELSE ' days. ' END ||
          'Cancel anytime from App Store settings.'
      END,
      jsonb_build_object(
        'type', 'subscription_trial_reminder',
        'subscription_id', ft.subscription_id,
        'trial_ends_at', ft.current_period_end,
        'deeplink', 'tidex://settings/subscription'
      ),
      'subscription_trial_reminder:' || ft.subscription_id::text || ':' ||
        to_char(ft.current_period_end AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS')
    FROM filtered_trials ft
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING 1
  )
  SELECT count(*)::integer
  INTO v_inserted_count
  FROM inserted;

  RETURN COALESCE(v_inserted_count, 0);
END;
$function$;
