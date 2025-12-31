-- Function: get_tariff_rate
-- Description: Returns the tariff rate for a given level (Norwegian wage table)
-- Used by: Payroll calculations

CREATE OR REPLACE FUNCTION public.get_tariff_rate(level smallint)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF level = 0 OR level IS NULL THEN
    RETURN NULL; -- 0 => use custom wage
  END IF;
  RETURN CASE level
    WHEN -1 THEN 129.91
    WHEN -2 THEN 132.90
    WHEN 1 THEN 188.58
    WHEN 2 THEN 200.32
    WHEN 3 THEN 208.70
    WHEN 4 THEN 222.58
    WHEN 5 THEN 238.10
    WHEN 6 THEN 256.14
    ELSE NULL
  END;
END;
$function$;
