ALTER TABLE public.payroll_adjustments
  ADD COLUMN IF NOT EXISTS curated_description text,
  ADD COLUMN IF NOT EXISTS curated_link_title text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'payroll_adjustments_curated_description_check'
  ) THEN
    ALTER TABLE public.payroll_adjustments
      ADD CONSTRAINT payroll_adjustments_curated_description_check CHECK (
        curated_description IS NULL OR length(curated_description) <= 2000
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'payroll_adjustments_curated_link_title_check'
  ) THEN
    ALTER TABLE public.payroll_adjustments
      ADD CONSTRAINT payroll_adjustments_curated_link_title_check CHECK (
        curated_link_title IS NULL OR length(btrim(curated_link_title)) BETWEEN 1 AND 120
      );
  END IF;
END $$;
