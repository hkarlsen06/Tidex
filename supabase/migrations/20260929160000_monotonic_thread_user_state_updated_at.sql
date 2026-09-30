-- The iOS app now orders read states by thread_user_state.updated_at and drops ones older than
-- what it has stored. now() is the transaction start time, so concurrent updates of one row could
-- commit an older value than the row they replaced. This trigger makes the value grow with every
-- update of the row.

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

DROP TRIGGER IF EXISTS thread_user_state_set_updated_at ON public.thread_user_state;
CREATE TRIGGER thread_user_state_set_updated_at
  BEFORE UPDATE ON public.thread_user_state
  FOR EACH ROW
  EXECUTE FUNCTION public.set_thread_user_state_updated_at();
