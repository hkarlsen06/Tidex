-- Function: queue_shift_added_notification
-- Description: Enqueues a simple friend notification when a non-recurring shift is added.
-- Used by: AFTER INSERT trigger on user_shifts

CREATE OR REPLACE FUNCTION public.queue_shift_added_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_owner_name text;
  v_owner_avatar_url text;
  v_recipient record;
  v_existing record;
  v_changes jsonb;
  v_display_changes jsonb;
  v_shift_dates jsonb;
  v_shift_count integer;
  v_existing_shift_count integer;
  v_dates_query text;
  v_deeplink text;
  v_body text;
  v_due_at timestamptz := now() + interval '90 seconds';
  v_has_existing boolean;
  v_is_duplicate boolean;
  v_payload_change_limit constant integer := 8;
  v_payload_date_limit constant integer := 31;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT
    COALESCE(au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name', au.email, 'Someone'),
    COALESCE(us.profile_picture_url, au.raw_user_meta_data->>'avatar_url')
  INTO v_owner_name, v_owner_avatar_url
  FROM auth.users au
  LEFT JOIN public.user_settings us
    ON us.user_id = au.id
  WHERE au.id = NEW.user_id;

  v_owner_name := COALESCE(v_owner_name, 'Someone');

  FOR v_recipient IN
    SELECT
      ss.viewer_id,
      COALESCE(au.raw_user_meta_data->>'locale', 'en') AS locale
    FROM public.shift_shares ss
    LEFT JOIN auth.users au
      ON au.id = ss.viewer_id
    LEFT JOIN public.notification_preferences np
      ON np.user_id = ss.viewer_id
    WHERE ss.owner_id = NEW.user_id
      AND ss.viewer_id <> NEW.user_id
      AND ss.blocked_by_user_id IS NULL
      AND COALESCE(ss.hidden, false) = false
      AND COALESCE(ss.muted, false) = false
      AND COALESCE(ss.owner_muted, false) = false
      AND COALESCE(np.shared_shifts_enabled, true) = true
  LOOP
    SELECT no.id, no.data_payload
    INTO v_existing
    FROM internal.notifications_outbox no
    WHERE no.owner_id = NEW.user_id
      AND no.recipient_id = v_recipient.viewer_id
      AND no.notification_type = 'shared_shift_added'
      AND no.status = 'pending'
      AND no.due_at > now()
    ORDER BY no.created_at DESC
    LIMIT 1
    FOR UPDATE;

    v_has_existing := FOUND;
    v_is_duplicate := false;

    IF v_has_existing THEN
      v_changes := COALESCE(
        v_existing.data_payload->'_internal_changes',
        v_existing.data_payload->'changes',
        '[]'::jsonb
      );
      v_existing_shift_count := GREATEST(
        COALESCE(NULLIF(v_existing.data_payload->>'total_change_count', '')::integer, 0),
        COALESCE(NULLIF(v_existing.data_payload->>'shift_count', '')::integer, 0),
        jsonb_array_length(v_changes)
      );

      v_is_duplicate := EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_changes) AS change
        WHERE change->>'shift_id' = NEW.id::text
      );

      IF NOT v_is_duplicate THEN
        v_changes := v_changes || jsonb_build_array(
          jsonb_build_object(
            'shift_id', NEW.id,
            'date', NEW.shift_date,
            'op', 'added'
          )
        );
      END IF;
      v_shift_count := v_existing_shift_count + CASE WHEN v_is_duplicate THEN 0 ELSE 1 END;
    ELSE
      v_changes := jsonb_build_array(
        jsonb_build_object(
          'shift_id', NEW.id,
          'date', NEW.shift_date,
          'op', 'added'
        )
      );
      v_shift_count := 1;
    END IF;

    SELECT COALESCE(jsonb_agg(change), '[]'::jsonb)
    INTO v_display_changes
    FROM (
      SELECT change
      FROM jsonb_array_elements(v_changes) AS change
      ORDER BY change->>'date', change->>'shift_id'
      LIMIT v_payload_change_limit
    ) limited_changes;

    SELECT
      jsonb_agg(date_value ORDER BY date_value),
      string_agg(date_value, ',' ORDER BY date_value)
    INTO v_shift_dates, v_dates_query
    FROM (
      SELECT DISTINCT date_value
      FROM (
        SELECT jsonb_array_elements_text(
          CASE
            WHEN v_has_existing THEN COALESCE(v_existing.data_payload->'shift_dates', '[]'::jsonb)
            ELSE '[]'::jsonb
          END
        ) AS date_value
        UNION ALL
        SELECT change->>'date' AS date_value
        FROM jsonb_array_elements(v_changes) AS change
        WHERE change->>'date' IS NOT NULL
      ) all_dates
      ORDER BY date_value
      LIMIT v_payload_date_limit
    ) dates;

    v_deeplink := 'tidex://sharing?user=' || NEW.user_id::text || '&dates=' || COALESCE(v_dates_query, NEW.shift_date::text);
    v_body := internal.shared_shift_added_notification_body(v_recipient.locale, v_shift_count);

    IF v_has_existing THEN
      UPDATE internal.notifications_outbox
      SET
        due_at = v_due_at,
        title = v_owner_name,
        body = v_body,
        data_payload = jsonb_build_object(
          'type', 'shared_shift_added',
          'owner_id', NEW.user_id,
          'owner_name', v_owner_name,
          'sender_user_id', NEW.user_id,
          'sender_name', v_owner_name,
          'sender_avatar_url', v_owner_avatar_url,
          'shift_count', v_shift_count,
          'total_change_count', v_shift_count,
          'has_more_changes', v_shift_count > jsonb_array_length(v_display_changes),
          'shift_dates', COALESCE(v_shift_dates, '[]'::jsonb),
          'changes', v_display_changes,
          '_internal_changes', v_changes,
          'deeplink', v_deeplink
        ),
        updated_at = now()
      WHERE id = v_existing.id;
    ELSE
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
        NEW.user_id,
        v_recipient.viewer_id,
        'shared_shift_added',
        v_due_at,
        v_owner_name,
        v_body,
        jsonb_build_object(
          'type', 'shared_shift_added',
          'owner_id', NEW.user_id,
          'owner_name', v_owner_name,
          'sender_user_id', NEW.user_id,
          'sender_name', v_owner_name,
          'sender_avatar_url', v_owner_avatar_url,
          'shift_count', v_shift_count,
          'total_change_count', v_shift_count,
          'has_more_changes', v_shift_count > jsonb_array_length(v_display_changes),
          'shift_dates', COALESCE(v_shift_dates, '[]'::jsonb),
          'changes', v_display_changes,
          '_internal_changes', v_changes,
          'deeplink', v_deeplink
        ),
        'shared_shift_added:' || NEW.user_id::text || ':' || v_recipient.viewer_id::text || ':' || NEW.id::text
      )
      ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_shift_added_notify_friends ON public.user_shifts;
CREATE TRIGGER on_shift_added_notify_friends
  AFTER INSERT ON public.user_shifts
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_shift_added_notification();

REVOKE EXECUTE ON FUNCTION public.queue_shift_added_notification() FROM public;
REVOKE EXECUTE ON FUNCTION public.queue_shift_added_notification() FROM anon;
REVOKE EXECUTE ON FUNCTION public.queue_shift_added_notification() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.queue_shift_added_notification() TO service_role;
