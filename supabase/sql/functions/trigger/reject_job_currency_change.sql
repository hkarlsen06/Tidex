-- Function: reject_job_currency_change
-- Description:
--   Enforces immutable job currency after INSERT.

CREATE OR REPLACE FUNCTION public.reject_job_currency_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.currency IS DISTINCT FROM NEW.currency THEN
    RAISE EXCEPTION 'job currency is immutable' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;
