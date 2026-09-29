-- Function: set_thread_user_state_updated_at
-- Description: Sets thread_user_state.updated_at to a value that grows with every update of the row
-- Used by: BEFORE UPDATE trigger on public.thread_user_state

-- Clients use updated_at to drop read states that arrive out of order, so it has to follow
-- commit order. now() is the transaction start time, so a mark_thread_read that waited for a
-- concurrent unread count update could commit a smaller value than the row it replaced. A BEFORE
-- ROW trigger runs after the row lock, so clock_timestamp() here is later than the previous
-- commit, and GREATEST keeps it increasing if the clock steps back.
CREATE OR REPLACE FUNCTION public.set_thread_user_state_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  NEW.updated_at = GREATEST(clock_timestamp(), OLD.updated_at + interval '1 microsecond');
  RETURN NEW;
END;
$function$;
