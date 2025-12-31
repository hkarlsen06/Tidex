-- Function: jsonb_has_content
-- Description: Checks if a JSONB value has meaningful content (non-null, non-empty)
-- Used by: Various queries checking for optional JSONB data

CREATE OR REPLACE FUNCTION public.jsonb_has_content(val jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN val IS NULL THEN false
    WHEN jsonb_typeof(val) = 'array' THEN jsonb_array_length(val) > 0
    WHEN jsonb_typeof(val) = 'object' THEN val <> '{}'::jsonb
    ELSE true
  END;
$function$;
