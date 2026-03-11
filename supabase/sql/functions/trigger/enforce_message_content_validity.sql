-- Function: enforce_message_content_validity
-- Description: Prevents messages from committing without renderable content and rejects invalid metadata

CREATE OR REPLACE FUNCTION public.enforce_message_content_validity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_message_id uuid := COALESCE(NEW.id, OLD.id);
  v_body text;
  v_metadata jsonb;
  v_attachments jsonb;
BEGIN
  SELECT
    m.body,
    m.metadata,
    COALESCE(
      (
        SELECT jsonb_agg(jsonb_build_object('id', ma.id) ORDER BY ma.attachment_index ASC)
        FROM public.message_attachments ma
        WHERE ma.message_id = m.id
      ),
      '[]'::jsonb
    )
  INTO v_body, v_metadata, v_attachments
  FROM public.messages m
  WHERE m.id = v_message_id;

  PERFORM public.assert_message_metadata_validity(v_metadata);

  IF NOT public.message_has_renderable_content(v_body, v_attachments, v_metadata) THEN
    RAISE EXCEPTION 'A message must include text, at least one attachment, or supported rich content';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;
