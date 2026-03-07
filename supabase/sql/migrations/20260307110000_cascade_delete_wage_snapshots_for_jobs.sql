BEGIN;

ALTER TABLE public.wage_snapshots
  DROP CONSTRAINT IF EXISTS wage_snapshots_job_id_fkey_jobs;

ALTER TABLE public.wage_snapshots
  ADD CONSTRAINT wage_snapshots_job_id_fkey_jobs
  FOREIGN KEY (job_id)
  REFERENCES public.jobs(id)
  ON DELETE CASCADE;

COMMIT;
