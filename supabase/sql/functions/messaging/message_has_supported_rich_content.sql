-- Function: message_has_supported_rich_content
-- Description: Returns whether metadata contains a supported rich-content payload

CREATE OR REPLACE FUNCTION public.message_has_supported_rich_content(p_metadata jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT public.message_supported_rich_content_kind(p_metadata) IS NOT NULL;
$function$;
