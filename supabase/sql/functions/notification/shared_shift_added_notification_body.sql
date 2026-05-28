-- Function: shared_shift_added_notification_body
-- Description: Builds localized push copy for shared shift added notifications.
-- Used by: queue_shift_added_notification, cancel_shift_added_notification_for_deleted_shift

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
