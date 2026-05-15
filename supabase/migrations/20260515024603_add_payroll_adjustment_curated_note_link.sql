ALTER TABLE public.payroll_adjustments
  ADD COLUMN curated_note text,
  ADD COLUMN curated_link text,
  ADD CONSTRAINT payroll_adjustments_curated_note_check CHECK (
    curated_note IS NULL OR length(curated_note) <= 1000
  ),
  ADD CONSTRAINT payroll_adjustments_curated_link_check CHECK (
    curated_link IS NULL OR length(btrim(curated_link)) BETWEEN 1 AND 2048
  );
