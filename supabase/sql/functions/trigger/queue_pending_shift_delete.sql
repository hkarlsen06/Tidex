-- Function: queue_pending_shift_delete
-- Description: Trigger function that queues deleted shifts for deferred processing
-- Used by: AFTER DELETE trigger on user_shifts

CREATE OR REPLACE FUNCTION public.queue_pending_shift_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO pending_shift_deletes (
    deleted_shift_id,
    owner_id,
    shift_date,
    start_time,
    end_time,
    start_time_parsed,
    has_supplements
  ) VALUES (
    OLD.id,
    OLD.user_id,
    OLD.shift_date,
    OLD.start_time,
    OLD.end_time,
    try_parse_time(OLD.start_time),  -- Safe parse, returns NULL on failure
    jsonb_has_content(OLD.custom_supplements)
  )
  ON CONFLICT (deleted_shift_id) DO NOTHING;

  RETURN OLD;
END;
$function$;
