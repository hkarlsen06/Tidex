-- Function: sync_shift_shares_hidden_legacy_blocked
-- Description: Keeps legacy shift_shares.blocked and new shift_shares.hidden in sync
-- Used by: BEFORE INSERT OR UPDATE trigger on shift_shares

CREATE OR REPLACE FUNCTION public.sync_shift_shares_hidden_legacy_blocked()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.hidden := COALESCE(NEW.hidden, false);
    NEW.blocked := COALESCE(NEW.blocked, false);

    IF NEW.hidden IS DISTINCT FROM NEW.blocked THEN
      IF NEW.hidden = false AND NEW.blocked = true THEN
        NEW.hidden := NEW.blocked;
      ELSIF NEW.hidden = true AND NEW.blocked = false THEN
        NEW.blocked := NEW.hidden;
      ELSE
        RAISE EXCEPTION 'shift_shares.hidden and shift_shares.blocked must match during compatibility window';
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  IF NEW.hidden IS DISTINCT FROM OLD.hidden
     AND NEW.blocked IS DISTINCT FROM OLD.blocked THEN
    IF NEW.hidden IS DISTINCT FROM NEW.blocked THEN
      RAISE EXCEPTION 'shift_shares.hidden and shift_shares.blocked cannot diverge during compatibility window';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.hidden IS DISTINCT FROM OLD.hidden THEN
    NEW.blocked := NEW.hidden;
  ELSIF NEW.blocked IS DISTINCT FROM OLD.blocked THEN
    NEW.hidden := NEW.blocked;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS aa_shift_shares_sync_hidden_blocked ON public.shift_shares;
CREATE TRIGGER aa_shift_shares_sync_hidden_blocked
  BEFORE INSERT OR UPDATE ON public.shift_shares
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_shift_shares_hidden_legacy_blocked();
