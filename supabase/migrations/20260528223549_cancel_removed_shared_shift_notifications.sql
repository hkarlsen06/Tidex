-- Keep a full internal list of pending shared-shift additions so deletes inside
-- the batching window can remove the exact shift before delivery.

CREATE OR REPLACE FUNCTION internal.shared_shift_added_notification_body(
  p_locale text,
  p_shift_count integer
)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_temp'
AS $function$
DECLARE
  v_shift_count integer := GREATEST(COALESCE(p_shift_count, 1), 1);
  v_language text;
  v_normalized_locale text;
  v_message_templates jsonb := jsonb_build_object(
    'ar', jsonb_build_object('singular', 'أضاف وردية', 'plural', 'أضاف %s ورديات'),
    'bg', jsonb_build_object('singular', 'Добави смяна', 'plural', 'Добави %s смени'),
    'bn', jsonb_build_object('singular', 'একটি শিফট যোগ করেছেন', 'plural', '%sটি শিফট যোগ করেছেন'),
    'ca', jsonb_build_object('singular', 'Ha afegit un torn', 'plural', 'Ha afegit %s torns'),
    'cs', jsonb_build_object('singular', 'Přidal(a) směnu', 'plural', 'Přidal(a) %s směn'),
    'da', jsonb_build_object('singular', 'Tilføjede en vagt', 'plural', 'Tilføjede %s vagter'),
    'de', jsonb_build_object('singular', 'Hat eine Schicht hinzugefügt', 'plural', 'Hat %s Schichten hinzugefügt'),
    'el', jsonb_build_object('singular', 'Πρόσθεσε μια βάρδια', 'plural', 'Πρόσθεσε %s βάρδιες'),
    'en', jsonb_build_object('singular', 'Added a shift', 'plural', 'Added %s shifts'),
    'es', jsonb_build_object('singular', 'Añadió un turno', 'plural', 'Añadió %s turnos'),
    'et', jsonb_build_object('singular', 'Lisas vahetuse', 'plural', 'Lisas %s vahetust'),
    'fa', jsonb_build_object('singular', 'یک شیفت اضافه کرد', 'plural', '%s شیفت اضافه کرد'),
    'fi', jsonb_build_object('singular', 'Lisäsi vuoron', 'plural', 'Lisäsi %s vuoroa'),
    'fil', jsonb_build_object('singular', 'Nagdagdag ng shift', 'plural', 'Nagdagdag ng %s shift'),
    'fr', jsonb_build_object('singular', 'A ajouté un service', 'plural', 'A ajouté %s services'),
    'he', jsonb_build_object('singular', 'הוסיף משמרת', 'plural', 'הוסיף %s משמרות'),
    'hi', jsonb_build_object('singular', 'एक शिफ्ट जोड़ी', 'plural', '%s शिफ्ट जोड़ीं'),
    'hr', jsonb_build_object('singular', 'Dodao/la je smjenu', 'plural', 'Dodao/la je %s smjena'),
    'hu', jsonb_build_object('singular', 'Hozzáadott egy műszakot', 'plural', 'Hozzáadott %s műszakot'),
    'id', jsonb_build_object('singular', 'Menambahkan satu shift', 'plural', 'Menambahkan %s shift'),
    'is', jsonb_build_object('singular', 'Bætti við vakt', 'plural', 'Bætti við %s vöktum'),
    'it', jsonb_build_object('singular', 'Ha aggiunto un turno', 'plural', 'Ha aggiunto %s turni'),
    'ja', jsonb_build_object('singular', 'シフトを追加しました', 'plural', '%s件のシフトを追加しました'),
    'ko', jsonb_build_object('singular', '근무를 추가했습니다', 'plural', '근무 %s개를 추가했습니다'),
    'lt', jsonb_build_object('singular', 'Pridėjo pamainą', 'plural', 'Pridėjo %s pamainas'),
    'lv', jsonb_build_object('singular', 'Pievienoja maiņu', 'plural', 'Pievienoja %s maiņas'),
    'nb', jsonb_build_object('singular', 'La til en vakt', 'plural', 'La til %s vakter'),
    'nl', jsonb_build_object('singular', 'Heeft een dienst toegevoegd', 'plural', 'Heeft %s diensten toegevoegd'),
    'nn', jsonb_build_object('singular', 'La til ei vakt', 'plural', 'La til %s vakter'),
    'pl', jsonb_build_object('singular', 'Dodał(a) zmianę', 'plural', 'Dodał(a) %s zmian'),
    'pt', jsonb_build_object('singular', 'Adicionou um turno', 'plural', 'Adicionou %s turnos'),
    'pt-br', jsonb_build_object('singular', 'Adicionou um turno', 'plural', 'Adicionou %s turnos'),
    'ro', jsonb_build_object('singular', 'A adăugat o tură', 'plural', 'A adăugat %s ture'),
    'ru', jsonb_build_object('singular', 'Добавил(а) смену', 'plural', 'Добавил(а) %s смен'),
    'sk', jsonb_build_object('singular', 'Pridal(a) zmenu', 'plural', 'Pridal(a) %s zmien'),
    'sl', jsonb_build_object('singular', 'Dodal(a) je izmeno', 'plural', 'Dodal(a) je %s izmen'),
    'sr', jsonb_build_object('singular', 'Dodao/la je smenu', 'plural', 'Dodao/la je %s smena'),
    'sv', jsonb_build_object('singular', 'Lade till ett pass', 'plural', 'Lade till %s pass'),
    'sw', jsonb_build_object('singular', 'Ameongeza zamu', 'plural', 'Ameongeza zamu %s'),
    'ta', jsonb_build_object('singular', 'ஒரு ஷிப்டைச் சேர்த்தார்', 'plural', '%s ஷிப்ட்களைச் சேர்த்தார்'),
    'th', jsonb_build_object('singular', 'เพิ่มกะทำงาน', 'plural', 'เพิ่มกะทำงาน %s กะ'),
    'tr', jsonb_build_object('singular', 'Bir vardiya ekledi', 'plural', '%s vardiya ekledi'),
    'uk', jsonb_build_object('singular', 'Додав(ла) зміну', 'plural', 'Додав(ла) %s змін'),
    'ur', jsonb_build_object('singular', 'ایک شفٹ شامل کی', 'plural', '%s شفٹیں شامل کیں'),
    'vi', jsonb_build_object('singular', 'Đã thêm một ca làm', 'plural', 'Đã thêm %s ca làm'),
    'zh', jsonb_build_object('singular', '添加了一个班次', 'plural', '添加了 %s 个班次'),
    'zh-hans', jsonb_build_object('singular', '添加了一个班次', 'plural', '添加了 %s 个班次'),
    'zh-hant', jsonb_build_object('singular', '新增了一個班次', 'plural', '新增了 %s 個班次')
  );
BEGIN
  v_normalized_locale := lower(replace(COALESCE(p_locale, 'en'), '_', '-'));
  v_language := CASE
    WHEN v_normalized_locale LIKE 'pt-br%' THEN 'pt-br'
    WHEN v_normalized_locale LIKE 'zh-hans%' THEN 'zh-hans'
    WHEN v_normalized_locale LIKE 'zh-hant%' THEN 'zh-hant'
    WHEN split_part(v_normalized_locale, '-', 1) = 'no' THEN 'nb'
    ELSE split_part(v_normalized_locale, '-', 1)
  END;

  IF NOT v_message_templates ? v_language THEN
    v_language := 'en';
  END IF;

  RETURN CASE
    WHEN v_shift_count = 1 THEN v_message_templates->v_language->>'singular'
    ELSE format(v_message_templates->v_language->>'plural', v_shift_count)
  END;
END;
$function$;

REVOKE EXECUTE ON FUNCTION internal.shared_shift_added_notification_body(text, integer) FROM public;
REVOKE EXECUTE ON FUNCTION internal.shared_shift_added_notification_body(text, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION internal.shared_shift_added_notification_body(text, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION internal.shared_shift_added_notification_body(text, integer) TO service_role;

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

UPDATE internal.notifications_outbox
SET
  data_payload = data_payload || jsonb_build_object(
    '_internal_changes',
    COALESCE(data_payload->'changes', '[]'::jsonb)
  ),
  updated_at = now()
WHERE notification_type = 'shared_shift_added'
  AND status = 'pending'
  AND due_at > now()
  AND NOT (data_payload ? '_internal_changes');
