-- Run against a database containing the migration. All fixture changes roll back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = '20s';
SET LOCAL lock_timeout = '5s';

-- Reuse the development account only as an owner of temporary test records.
SELECT set_config('request.jwt.claims', '{"sub":"032d8c2a-9af6-4777-99f0-24e2c4058bf3","role":"authenticated","aal":"aal2"}', true);
CREATE TEMP TABLE deletion_test_ids AS SELECT gen_random_uuid() AS job_id, gen_random_uuid() AS other_job_id, gen_random_uuid() AS empty_job_id;
GRANT SELECT ON deletion_test_ids TO authenticated;
INSERT INTO public.jobs (id, user_id, name)
SELECT job_id, auth.uid(), 'Deletion regression fixture' FROM deletion_test_ids
UNION ALL SELECT other_job_id, auth.uid(), 'Unrelated deletion regression fixture' FROM deletion_test_ids
UNION ALL SELECT empty_job_id, auth.uid(), 'Empty deletion regression fixture' FROM deletion_test_ids;
INSERT INTO public.user_shifts (user_id, job_id, shift_date, start_time, end_time)
SELECT auth.uid(), job_id, DATE '2026-01-12', '09:00', '17:00' FROM deletion_test_ids
UNION ALL SELECT auth.uid(), other_job_id, DATE '2026-01-12', '09:00', '17:00' FROM deletion_test_ids;
INSERT INTO public.recurring_shifts (user_id, job_id, start_time, end_time, repeat_interval_weeks, selected_days)
SELECT auth.uid(), job_id, TIMETZ '09:00+00', TIMETZ '17:00+00', 1, '[1]'::jsonb FROM deletion_test_ids;
INSERT INTO public.payroll_adjustments (user_id, job_id, amount, category, description, payout_date)
SELECT auth.uid(), job_id, 100, 'bonus', 'Deletion regression fixture', DATE '2026-01-31' FROM deletion_test_ids;
INSERT INTO public.wage_snapshots (user_id, job_id, hourly_wage)
SELECT auth.uid(), job_id, 200 FROM deletion_test_ids;

SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_id uuid := (SELECT job_id FROM deletion_test_ids);
  v_preview jsonb;
  v_receipt jsonb;
BEGIN
  -- Active jobs are rejected, even with a supplied confirmation token.
  BEGIN
    PERFORM public.delete_archived_job(v_id, 'unexpected');
    RAISE EXCEPTION 'active workplace was accepted';
  EXCEPTION WHEN SQLSTATE 'PT400' THEN NULL;
  END;
  UPDATE public.jobs SET archived_at = now() WHERE id = v_id;
  v_preview := public.delete_archived_job(v_id);
  ASSERT (v_preview->>'user_shifts')::int = 1;
  ASSERT (v_preview->>'recurring_shifts')::int = 1;
  ASSERT (v_preview->>'payroll_adjustments')::int = 1;
  ASSERT (v_preview->>'wage_snapshots')::int = 1;
  ASSERT v_preview->>'deleted_at_epoch' IS NULL;
  ASSERT (SELECT deleted_at IS NULL FROM public.jobs WHERE id = v_id);

  -- Another owner cannot preview or delete this job.
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
  BEGIN
    PERFORM public.delete_archived_job(v_id, v_preview->>'confirmation_token');
    RAISE EXCEPTION 'another owner was accepted';
  EXCEPTION WHEN SQLSTATE 'PT404' THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', '{"sub":"032d8c2a-9af6-4777-99f0-24e2c4058bf3","role":"authenticated","aal":"aal2"}', true);

  -- Changes with identical counts still invalidate the confirmation.
  UPDATE public.user_shifts SET end_time = '18:00' WHERE job_id = v_id;
  BEGIN
    PERFORM public.delete_archived_job(v_id, v_preview->>'confirmation_token');
    RAISE EXCEPTION 'stale confirmation was accepted';
  EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL;
  END;
  ASSERT (SELECT deleted_at IS NULL FROM public.jobs WHERE id = v_id);
  ASSERT (SELECT count(*) FROM public.user_shifts WHERE job_id = v_id AND deleted_at IS NULL) = 1;

  -- Restoring an archived job also invalidates deletion.
  UPDATE public.jobs SET archived_at = NULL WHERE id = v_id;
  BEGIN
    PERFORM public.delete_archived_job(v_id, v_preview->>'confirmation_token');
    RAISE EXCEPTION 'restored workplace was accepted';
  EXCEPTION WHEN SQLSTATE 'PT400' THEN NULL;
  END;
  UPDATE public.jobs SET archived_at = now() WHERE id = v_id;
END;
$test$;
RESET ROLE;

-- Force a late write failure and verify earlier deletions are rolled back.
CREATE FUNCTION public.deletion_test_reject_adjustment() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  IF NEW.job_id = (SELECT job_id FROM deletion_test_ids) AND NEW.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'injected deletion failure' USING ERRCODE = 'PT418';
  END IF;
  RETURN NEW;
END;
$fn$;
CREATE TRIGGER deletion_test_reject_adjustment BEFORE UPDATE OF deleted_at ON public.payroll_adjustments
FOR EACH ROW EXECUTE FUNCTION public.deletion_test_reject_adjustment();
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_id uuid := (SELECT job_id FROM deletion_test_ids);
  v_preview jsonb := public.delete_archived_job(v_id);
BEGIN
  BEGIN
    PERFORM public.delete_archived_job(v_id, v_preview->>'confirmation_token');
    RAISE EXCEPTION 'injected deletion failure was ignored';
  EXCEPTION WHEN SQLSTATE 'PT418' THEN NULL;
  END;
  ASSERT (SELECT deleted_at IS NULL FROM public.jobs WHERE id = v_id);
  ASSERT (SELECT count(*) FROM public.user_shifts WHERE job_id = v_id AND deleted_at IS NULL) = 1;
  ASSERT (SELECT count(*) FROM public.recurring_shifts WHERE job_id = v_id AND deleted_at IS NULL) = 1;
  ASSERT (SELECT count(*) FROM public.payroll_adjustments WHERE job_id = v_id AND deleted_at IS NULL) = 1;
END;
$test$;
RESET ROLE;
DROP TRIGGER deletion_test_reject_adjustment ON public.payroll_adjustments;
DROP FUNCTION public.deletion_test_reject_adjustment();
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_id uuid := (SELECT job_id FROM deletion_test_ids);
  v_preview jsonb := public.delete_archived_job(v_id);
  v_receipt jsonb;
BEGIN
  v_receipt := public.delete_archived_job(v_id, v_preview->>'confirmation_token');
  ASSERT v_receipt->>'deleted_at_epoch' IS NOT NULL;
  ASSERT (SELECT deleted_at IS NOT NULL FROM public.jobs WHERE id = v_id);
  ASSERT (SELECT count(*) FROM public.user_shifts WHERE job_id = v_id AND deleted_at IS NULL) = 0;
  ASSERT (SELECT count(*) FROM public.recurring_shifts WHERE job_id = v_id AND deleted_at IS NULL) = 0;
  ASSERT (SELECT count(*) FROM public.payroll_adjustments WHERE job_id = v_id AND deleted_at IS NULL) = 0;
  ASSERT (SELECT count(*) FROM public.wage_snapshots WHERE job_id = v_id AND deleted_at IS NULL) = 0;
  ASSERT (SELECT count(*) FROM public.user_shifts WHERE job_id = (SELECT other_job_id FROM deletion_test_ids) AND deleted_at IS NULL) = 1;
  ASSERT (SELECT deleted_at IS NULL FROM public.jobs WHERE id = (SELECT other_job_id FROM deletion_test_ids));
  ASSERT public.delete_archived_job(v_id, v_preview->>'confirmation_token')->>'deleted_at_epoch' = v_receipt->>'deleted_at_epoch';

  -- Empty archived workplaces also use the same explicit confirmation flow.
  v_id := (SELECT empty_job_id FROM deletion_test_ids);
  UPDATE public.jobs SET archived_at = now() WHERE id = v_id;
  v_preview := public.delete_archived_job(v_id);
  ASSERT (v_preview->>'user_shifts')::int = 0;
  ASSERT (v_preview->>'recurring_shifts')::int = 0;
  ASSERT (v_preview->>'payroll_adjustments')::int = 0;
  ASSERT (v_preview->>'wage_snapshots')::int = 0;
  PERFORM public.delete_archived_job(v_id, v_preview->>'confirmation_token');
  ASSERT (SELECT deleted_at IS NOT NULL FROM public.jobs WHERE id = v_id);
END;
$test$;
RESET ROLE;
DO $test$
BEGIN
  ASSERT NOT has_function_privilege('anon', 'public.delete_archived_job(uuid,text)', 'EXECUTE');
  ASSERT has_function_privilege('authenticated', 'public.delete_archived_job(uuid,text)', 'EXECUTE');
  ASSERT NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.delete_archived_job(uuid,text)'::regprocedure);
END;
$test$;
ROLLBACK;
\echo 'Archived workplace deletion regression checks passed (rolled back).'
