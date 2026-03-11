-- Function: message_has_renderable_content
-- Description: Returns whether a message has text, attachments, or supported rich content

CREATE OR REPLACE FUNCTION public.message_has_renderable_content(
  p_body text,
  p_attachments jsonb,
  p_metadata jsonb
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT
    NULLIF(regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'), '') IS NOT NULL
    OR (
      CASE
        WHEN COALESCE(jsonb_typeof(p_attachments), 'array') = 'array'
          THEN jsonb_array_length(COALESCE(p_attachments, '[]'::jsonb)) > 0
        ELSE false
      END
    )
    OR public.message_has_supported_rich_content(p_metadata);
$function$;
