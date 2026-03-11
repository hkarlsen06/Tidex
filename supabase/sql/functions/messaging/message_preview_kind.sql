-- Function: message_preview_kind
-- Description: Derives the canonical preview kind for message summaries and fallbacks

CREATE OR REPLACE FUNCTION public.message_preview_kind(
  p_body text,
  p_metadata jsonb,
  p_has_image boolean
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  WITH supported_kind AS (
    SELECT public.message_supported_rich_content_kind(p_metadata) AS kind
  )
  SELECT CASE
    WHEN NULLIF(regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'), '') IS NOT NULL THEN 'text'
    WHEN COALESCE(p_has_image, false) THEN 'image'
    WHEN supported_kind.kind IS NOT NULL THEN supported_kind.kind
    ELSE 'unknown'
  END
  FROM supported_kind;
$function$;
