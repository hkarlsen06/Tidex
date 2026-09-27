-- Run against a database containing 20260927130000..20260927130200.
-- All fixture changes roll back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = '20s';
SET LOCAL lock_timeout = '5s';

CREATE TEMP TABLE share_test_ids AS
SELECT gen_random_uuid() AS owner_id, gen_random_uuid() AS viewer_id, gen_random_uuid() AS job_id;
GRANT SELECT ON share_test_ids TO authenticated;

INSERT INTO auth.users (id, instance_id, aud, role, email)
SELECT owner_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', owner_id || '@share-test.invalid' FROM share_test_ids
UNION ALL
SELECT viewer_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', viewer_id || '@share-test.invalid' FROM share_test_ids;

INSERT INTO public.user_settings (user_id)
SELECT owner_id FROM share_test_ids
ON CONFLICT (user_id) DO NOTHING;
INSERT INTO public.jobs (id, user_id, name)
SELECT job_id, owner_id, 'Share RLS fixture' FROM share_test_ids;
INSERT INTO public.wage_snapshots (user_id, job_id, hourly_wage)
SELECT owner_id, job_id, 200 FROM share_test_ids;
INSERT INTO public.shift_shares (owner_id, viewer_id, show_earnings)
SELECT owner_id, viewer_id, false FROM share_test_ids;

-- Act as the viewer.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', viewer_id, 'role', 'authenticated', 'aal', 'aal1')::text, true)
FROM share_test_ids;

DO $test$
DECLARE
  v_owner uuid := (SELECT owner_id FROM share_test_ids);
  v_rows integer;
BEGIN
  -- show_earnings = false hides wage snapshots but not settings.
  ASSERT NOT EXISTS (SELECT 1 FROM public.wage_snapshots WHERE user_id = v_owner), 'wage snapshot visible without show_earnings';
  ASSERT EXISTS (SELECT 1 FROM public.user_settings WHERE user_id = v_owner), 'shared settings not visible';

  -- A viewer cannot write the owner's settings.
  UPDATE public.user_settings SET theme = 'dark' WHERE user_id = v_owner;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  ASSERT v_rows = 0, 'viewer updated owner settings';
  DELETE FROM public.user_settings WHERE user_id = v_owner;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  ASSERT v_rows = 0, 'viewer deleted owner settings';

  -- Direct inserts skip the share limit, so RLS refuses them.
  BEGIN
    INSERT INTO public.shift_shares (owner_id, viewer_id) VALUES (auth.uid(), v_owner);
    RAISE EXCEPTION 'direct shift_shares insert was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$test$;

-- The owner blocks the viewer.
SELECT set_config('request.jwt.claims', json_build_object('sub', owner_id, 'role', 'authenticated', 'aal', 'aal1')::text, true)
FROM share_test_ids;
SELECT public.block_user_pair(viewer_id) FROM share_test_ids;

SELECT set_config('request.jwt.claims', json_build_object('sub', viewer_id, 'role', 'authenticated', 'aal', 'aal1')::text, true)
FROM share_test_ids;

DO $test$
DECLARE
  v_owner uuid := (SELECT owner_id FROM share_test_ids);
  v_rows integer;
BEGIN
  ASSERT NOT EXISTS (SELECT 1 FROM public.user_settings WHERE user_id = v_owner), 'blocked viewer still reads settings';

  -- The blocked party cannot delete the block or share across it.
  DELETE FROM public.shift_shares WHERE owner_id = v_owner AND viewer_id = auth.uid();
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  ASSERT v_rows = 0, 'blocked viewer deleted the blocked share';
  ASSERT NOT (public.manage_sharing_action('shareBack', NULL, v_owner) ->> 'success')::boolean, 'shared across a block';
END;
$test$;

-- is_admin() requires aal2.
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub":"032d8c2a-9af6-4777-99f0-24e2c4058bf3","role":"authenticated","aal":"aal1"}', true);
DO $test$ BEGIN ASSERT NOT public.is_admin(), 'is_admin() accepted aal1'; END; $test$;
SELECT set_config('request.jwt.claims', '{"sub":"032d8c2a-9af6-4777-99f0-24e2c4058bf3","role":"authenticated","aal":"aal2"}', true);
DO $test$ BEGIN ASSERT public.is_admin(), 'is_admin() rejected aal2 admin'; END; $test$;

ROLLBACK;
