-- Function: cancel_shift_added_notification_for_deleted_shift
-- Description: Removes soft-deleted shifts from pending shared-shift added notifications.
-- Used by: AFTER UPDATE OF deleted_at trigger on user_shifts

CREATE OR REPLACE FUNCTION public.cancel_shift_added_notification_for_deleted_shift()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_notification record;
  v_changes jsonb;
  v_display_changes jsonb;
  v_shift_dates jsonb;
  v_shift_count integer;
  v_dates_query text;
  v_deeplink text;
  v_body text;
  v_recipient_locale text;
  v_payload_change_limit constant integer := 8;
  v_payload_date_limit constant integer := 31;
BEGIN
  IF OLD.deleted_at IS NOT NULL OR NEW.deleted_at IS NULL THEN
    RETURN NEW;
  END IF;

  FOR v_notification IN
    SELECT no.id, no.recipient_id, no.data_payload
    FROM internal.notifications_outbox no
    WHERE no.owner_id = NEW.user_id
      AND no.notification_type = 'shared_shift_added'
      AND no.status IN ('pending', 'sending')
    ORDER BY no.created_at DESC
    FOR UPDATE
  LOOP
    v_changes := COALESCE(
      v_notification.data_payload->'_internal_changes',
      v_notification.data_payload->'changes',
      '[]'::jsonb
    );

    IF NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(v_changes) AS change
      WHERE change->>'shift_id' = NEW.id::text
    ) THEN
      CONTINUE;
    END IF;

    SELECT COALESCE(jsonb_agg(change ORDER BY change->>'date', change->>'shift_id'), '[]'::jsonb)
    INTO v_changes
    FROM jsonb_array_elements(v_changes) AS change
    WHERE change->>'shift_id' <> NEW.id::text;

    v_shift_count := jsonb_array_length(v_changes);

    IF v_shift_count = 0 THEN
      UPDATE internal.notifications_outbox
      SET
        status = 'skipped',
        processed_at = now(),
        error_message = 'All queued shared shift additions were removed before delivery',
        data_payload = v_notification.data_payload || jsonb_build_object(
          'shift_count', 0,
          'total_change_count', 0,
          'has_more_changes', false,
          'shift_dates', '[]'::jsonb,
          'changes', '[]'::jsonb,
          '_internal_changes', '[]'::jsonb
        ),
        updated_at = now()
      WHERE id = v_notification.id;

      CONTINUE;
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
      SELECT DISTINCT change->>'date' AS date_value
      FROM jsonb_array_elements(v_changes) AS change
      WHERE change->>'date' IS NOT NULL
      ORDER BY date_value
      LIMIT v_payload_date_limit
    ) dates;

    SELECT COALESCE(au.raw_user_meta_data->>'locale', 'en')
    INTO v_recipient_locale
    FROM auth.users au
    WHERE au.id = v_notification.recipient_id;

    v_deeplink := 'tidex://sharing?user=' || NEW.user_id::text || '&dates=' || COALESCE(v_dates_query, NEW.shift_date::text);
    v_body := internal.shared_shift_added_notification_body(v_recipient_locale, v_shift_count);

    UPDATE internal.notifications_outbox
    SET
      body = v_body,
      data_payload = v_notification.data_payload || jsonb_build_object(
        'shift_count', v_shift_count,
        'total_change_count', v_shift_count,
        'has_more_changes', v_shift_count > jsonb_array_length(v_display_changes),
        'shift_dates', COALESCE(v_shift_dates, '[]'::jsonb),
        'changes', v_display_changes,
        '_internal_changes', v_changes,
        'deeplink', v_deeplink
      ),
      updated_at = now()
    WHERE id = v_notification.id;
  END LOOP;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_shift_deleted_cancel_added_notification ON public.user_shifts;
CREATE TRIGGER on_shift_deleted_cancel_added_notification
  AFTER UPDATE OF deleted_at ON public.user_shifts
  FOR EACH ROW
  WHEN (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL)
  EXECUTE FUNCTION public.cancel_shift_added_notification_for_deleted_shift();

REVOKE EXECUTE ON FUNCTION public.cancel_shift_added_notification_for_deleted_shift() FROM public;
REVOKE EXECUTE ON FUNCTION public.cancel_shift_added_notification_for_deleted_shift() FROM anon;
REVOKE EXECUTE ON FUNCTION public.cancel_shift_added_notification_for_deleted_shift() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_shift_added_notification_for_deleted_shift() TO service_role;
