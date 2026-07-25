CREATE OR REPLACE FUNCTION public.set_wage_snapshots_deleted_at_from_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Only act when deleted_at changes from NULL to a value
  IF TG_OP = 'UPDATE' AND OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    UPDATE public.wage_snapshots ws
    SET deleted_at = NEW.deleted_at,
        updated_at = NOW()
    WHERE ws.job_id = NEW.id
      AND (ws.deleted_at IS DISTINCT FROM NEW.deleted_at);
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.set_wage_snapshots_deleted_at_from_job()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_wage_snapshots_deleted_at_from_job()
  TO service_role;
