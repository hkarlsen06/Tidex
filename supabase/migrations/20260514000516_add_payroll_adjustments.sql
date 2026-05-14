CREATE TABLE public.payroll_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  job_id uuid REFERENCES public.jobs(id) ON DELETE SET NULL,
  amount numeric NOT NULL,
  currency text NOT NULL DEFAULT 'kr',
  category text NOT NULL,
  tax_treatment text NOT NULL DEFAULT 'gross_taxable',
  title text NOT NULL,
  note text,
  earned_from_date date,
  earned_to_date date,
  payout_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  revision bigint NOT NULL DEFAULT 1,
  deleted_at timestamptz,
  CONSTRAINT payroll_adjustments_category_check CHECK (
    category IN ('retro_pay', 'bonus', 'correction', 'other')
  ),
  CONSTRAINT payroll_adjustments_tax_treatment_check CHECK (
    tax_treatment IN ('gross_taxable', 'net_manual', 'excluded_from_tax_estimate')
  ),
  CONSTRAINT payroll_adjustments_title_check CHECK (
    length(btrim(title)) BETWEEN 1 AND 120
  ),
  CONSTRAINT payroll_adjustments_currency_check CHECK (
    length(btrim(currency)) BETWEEN 1 AND 12
  ),
  CONSTRAINT payroll_adjustments_note_check CHECK (
    note IS NULL OR length(note) <= 1000
  ),
  CONSTRAINT payroll_adjustments_earned_range_check CHECK (
    earned_from_date IS NULL
    OR earned_to_date IS NULL
    OR earned_from_date <= earned_to_date
  )
);

CREATE INDEX idx_payroll_adjustments_user_updated
  ON public.payroll_adjustments (user_id, updated_at, id);

CREATE INDEX idx_payroll_adjustments_user_payout
  ON public.payroll_adjustments (user_id, payout_date)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_payroll_adjustments_job_id
  ON public.payroll_adjustments (job_id);

CREATE OR REPLACE FUNCTION public.validate_payroll_adjustment_job_owner()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.job_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.jobs j
    WHERE j.id = NEW.job_id
      AND j.user_id = NEW.user_id
      AND j.deleted_at IS NULL
      AND j.archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'job_id must belong to same user';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER validate_payroll_adjustment_job_owner
  BEFORE INSERT OR UPDATE OF user_id, job_id ON public.payroll_adjustments
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_payroll_adjustment_job_owner();

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

CREATE TRIGGER set_payroll_adjustments_updated_at_revision
  BEFORE UPDATE ON public.payroll_adjustments
  FOR EACH ROW
  EXECUTE FUNCTION public.set_payroll_adjustments_updated_at_and_revision();

ALTER TABLE public.payroll_adjustments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Require MFA for users who enrolled"
  ON public.payroll_adjustments
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (check_mfa_aal());

CREATE POLICY "Users can view own payroll adjustments"
  ON public.payroll_adjustments
  FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid() AS uid));

CREATE POLICY "Users can insert own payroll adjustments"
  ON public.payroll_adjustments
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid() AS uid));

CREATE POLICY "Users can update own payroll adjustments"
  ON public.payroll_adjustments
  FOR UPDATE
  TO authenticated
  USING (user_id = (SELECT auth.uid() AS uid))
  WITH CHECK (user_id = (SELECT auth.uid() AS uid));

CREATE POLICY "Users can delete own payroll adjustments"
  ON public.payroll_adjustments
  FOR DELETE
  TO authenticated
  USING (user_id = (SELECT auth.uid() AS uid));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.payroll_adjustments TO authenticated;
