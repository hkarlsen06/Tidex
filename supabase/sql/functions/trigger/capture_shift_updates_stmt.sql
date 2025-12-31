-- Function: capture_shift_updates_stmt
-- Description: Trigger function that captures shift updates with meaningful changes (date/time)
-- Used by: AFTER UPDATE trigger on user_shifts (statement-level)

CREATE OR REPLACE FUNCTION public.capture_shift_updates_stmt()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Insert update events for shifts with meaningful changes (date or times changed)
  INSERT INTO shift_update_events (shift_id, owner_id, shift_date, start_time, end_time)
  SELECT n.id, n.user_id, n.shift_date, n.start_time, n.end_time
  FROM new_rows n
  JOIN old_rows o ON o.id = n.id
  WHERE (n.shift_date IS DISTINCT FROM o.shift_date)
     OR (n.start_time IS DISTINCT FROM o.start_time)
     OR (n.end_time IS DISTINCT FROM o.end_time);

  RETURN NULL;
END;
$function$;
