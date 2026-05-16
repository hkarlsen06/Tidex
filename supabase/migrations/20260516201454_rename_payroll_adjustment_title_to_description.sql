DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'payroll_adjustments'
      AND column_name = 'title'
  ) AND NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'payroll_adjustments'
      AND column_name = 'description'
  ) THEN
    ALTER TABLE public.payroll_adjustments
      RENAME COLUMN title TO description;
  END IF;
END $$;

ALTER TABLE public.payroll_adjustments
  DROP CONSTRAINT IF EXISTS payroll_adjustments_title_check;

ALTER TABLE public.payroll_adjustments
  DROP CONSTRAINT IF EXISTS payroll_adjustments_description_check;

ALTER TABLE public.payroll_adjustments
  ADD CONSTRAINT payroll_adjustments_description_check CHECK (
    length(btrim(description)) BETWEEN 1 AND 240
  );

COMMENT ON COLUMN public.payroll_adjustments.description IS
  'Short user-visible description of what the adjustment is and why it exists.';
