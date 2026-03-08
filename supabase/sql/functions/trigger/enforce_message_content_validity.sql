-- Function: enforce_message_content_validity
-- Description: Prevents messages from committing without either text content or at least one attachment

CREATE OR REPLACE FUNCTION public.enforce_message_content_validity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_message_id uuid := COALESCE(NEW.id, OLD.id);
  v_has_body boolean;
  v_attachment_count integer;
BEGIN
  SELECT
    NULLIF(regexp_replace(COALESCE(m.body, ''), '^\s+|\s+$', '', 'g'), '') IS NOT NULL,
    (
      SELECT count(*)
      FROM public.message_attachments ma
      WHERE ma.message_id = m.id
    )
  INTO v_has_body, v_attachment_count
  FROM public.messages m
  WHERE m.id = v_message_id;

  IF COALESCE(v_has_body, false) = false AND COALESCE(v_attachment_count, 0) = 0 THEN
    RAISE EXCEPTION 'A message must include text or at least one attachment';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;
