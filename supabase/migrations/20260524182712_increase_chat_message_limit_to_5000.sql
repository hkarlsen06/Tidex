DO $$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef('public.send_message(uuid, uuid, text, uuid, jsonb, jsonb)'::regprocedure)
  INTO v_definition;

  EXECUTE replace(
    replace(
      v_definition,
      'char_length(v_normalized_body) > 2000',
      'char_length(v_normalized_body) > 5000'
    ),
    'Message body exceeds the 2000 character limit',
    'Message body exceeds the 5000 character limit'
  );

  SELECT pg_get_functiondef('public.edit_message(uuid, text)'::regprocedure)
  INTO v_definition;

  EXECUTE replace(
    replace(
      v_definition,
      'char_length(v_normalized_body) > 2000',
      'char_length(v_normalized_body) > 5000'
    ),
    'Message body exceeds the 2000 character limit',
    'Message body exceeds the 5000 character limit'
  );
END $$;
