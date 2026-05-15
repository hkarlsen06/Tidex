-- Function: try_parse_time
-- Description: Safely parses a time string, returning NULL on failure
-- Used by: Various shift processing functions

CREATE OR REPLACE FUNCTION public.try_parse_time(val text)
 RETURNS time without time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF val IS NULL OR btrim(val) = '' THEN
    RETURN NULL;
  END IF;

  BEGIN
    RETURN val::time;
  EXCEPTION WHEN others THEN
    RETURN NULL;
  END;
END;
$function$;
