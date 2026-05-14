-- Function: set_payroll_adjustments_updated_at_and_revision
-- Description: Maintains updated_at and revision for payroll_adjustments sync rows.

CREATE OR REPLACE FUNCTION public.set_payroll_adjustments_updated_at_and_revision()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  NEW.updated_at = now();
  NEW.revision = OLD.revision + 1;
  RETURN NEW;
END;
$function$;
