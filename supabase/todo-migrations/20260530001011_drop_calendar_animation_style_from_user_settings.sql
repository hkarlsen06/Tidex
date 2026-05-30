DO $$
DECLARE
  function_signature text;
  function_oid oid;
  function_definition text;
BEGIN
  FOREACH function_signature IN ARRAY ARRAY[
    'public.get_my_sharer_preview_payloads(uuid[], date, date)',
    'public.get_friends_tab_bootstrap(date, date)',
    'public.get_shared_month_payload(uuid, integer, integer)'
  ]
  LOOP
    function_oid := to_regprocedure(function_signature)::oid;

    IF function_oid IS NULL THEN
      CONTINUE;
    END IF;

    function_definition := pg_get_functiondef(function_oid);
    function_definition := regexp_replace(
      function_definition,
      ',\s*''calendar_animation_style'',\s*us\.calendar_animation_style',
      '',
      'g'
    );
    EXECUTE function_definition;
  END LOOP;
END $$;

ALTER TABLE public.user_settings
  DROP COLUMN IF EXISTS calendar_animation_style;
