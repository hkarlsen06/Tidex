-- Function: ensure_job_currency_on_insert
-- Description:
--   Backward-compatibility guard for legacy clients that send jobs.currency as NULL.
--   Prefers user_settings.currency, then falls back to 'kr'.

CREATE OR REPLACE FUNCTION public.ensure_job_currency_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.currency IS NULL THEN
    SELECT COALESCE(us.currency, 'kr')
    INTO NEW.currency
    FROM public.user_settings us
    WHERE us.user_id = NEW.user_id
    LIMIT 1;

    NEW.currency := COALESCE(NEW.currency, 'kr');
  END IF;

  RETURN NEW;
END;
$$;
