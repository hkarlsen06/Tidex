-- Function: set_jobs_updated_at_and_revision
-- Description:
--   Trigger function for jobs table. Sets updated_at and increments revision.

CREATE OR REPLACE FUNCTION public.set_jobs_updated_at_and_revision()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  NEW.revision := COALESCE(OLD.revision, 0) + 1;
  RETURN NEW;
END;
$$;
