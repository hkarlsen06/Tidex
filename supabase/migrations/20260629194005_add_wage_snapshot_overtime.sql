ALTER TABLE public.wage_snapshots
  ADD COLUMN IF NOT EXISTS overtime jsonb NOT NULL DEFAULT
    '{"enabled": false, "weeklyThresholdHours": 40, "rules": []}'::jsonb;

COMMENT ON COLUMN public.wage_snapshots.overtime IS
  'Per-snapshot overtime configuration. Structure: { enabled, weeklyThresholdHours, rules[] }.';

DO $$
DECLARE
  v_disabled_overtime text :=
    'jsonb_build_object(''enabled'', false, ''weeklyThresholdHours'', 40, ''rules'', jsonb_build_array())';
  v_visible_search text := '''supplements'', w.supplements,';
  v_hidden_search text := '''supplements'', jsonb_build_object(''rules'', jsonb_build_array()),';
  v_visible_replace text :=
    '''supplements'', w.supplements, ''overtime'', COALESCE(w.overtime, '
    || v_disabled_overtime || '),';
  v_hidden_replace text :=
    '''supplements'', jsonb_build_object(''rules'', jsonb_build_array()), ''overtime'', '
    || v_disabled_overtime || ',';
  v_sql text;
  v_signature_name text;
  v_signature regprocedure;
BEGIN
  FOREACH v_signature_name IN ARRAY ARRAY[
    'public.get_shared_month_payload(uuid, integer, integer)',
    'public.get_my_sharer_preview_payloads(uuid[], date, date)',
    'public.get_friends_tab_bootstrap(date, date)'
  ]
  LOOP
    v_signature := to_regprocedure(v_signature_name);
    CONTINUE WHEN v_signature IS NULL;

    SELECT pg_get_functiondef(v_signature) INTO v_sql;

    IF v_sql IS NOT NULL AND position('''overtime''' IN v_sql) = 0 THEN
      v_sql := replace(v_sql, v_visible_search, v_visible_replace);
      v_sql := replace(v_sql, v_hidden_search, v_hidden_replace);
      v_sql := replace(
        v_sql,
        'make_date(p_year, p_month, 1) AS start_date,
      ((make_date(p_year, p_month, 1) + interval ''1 month'')::date - 1) AS end_date',
        'make_date(p_year, p_month, 1) AS start_date,
      ((make_date(p_year, p_month, 1) + interval ''1 month'')::date - 1) AS end_date,
      (make_date(p_year, p_month, 1) - ((EXTRACT(isodow FROM make_date(p_year, p_month, 1))::integer - 1) * interval ''1 day''))::date AS calculation_start_date,
      (((make_date(p_year, p_month, 1) + interval ''1 month'')::date - 1) + ((7 - EXTRACT(isodow FROM ((make_date(p_year, p_month, 1) + interval ''1 month'')::date - 1))::integer) * interval ''1 day''))::date AS calculation_end_date'
      );
      v_sql := replace(v_sql, 's.shift_date >= mb.start_date', 's.shift_date >= mb.calculation_start_date');
      v_sql := replace(v_sql, 's.shift_date <= mb.end_date', 's.shift_date <= mb.calculation_end_date');
      v_sql := replace(
        v_sql,
        '(p_start_date IS NULL OR s.shift_date >= p_start_date)',
        '(p_start_date IS NULL OR s.shift_date >= (p_start_date - ((EXTRACT(isodow FROM p_start_date)::integer - 1) * interval ''1 day''))::date)'
      );
      v_sql := replace(
        v_sql,
        '(p_end_date IS NULL OR s.shift_date <= p_end_date)',
        '(p_end_date IS NULL OR s.shift_date <= (p_end_date + ((7 - EXTRACT(isodow FROM p_end_date)::integer) * interval ''1 day''))::date)'
      );
      v_sql := replace(
        v_sql,
        '(p_preview_start_date IS NULL OR s.shift_date >= p_preview_start_date)',
        '(p_preview_start_date IS NULL OR s.shift_date >= (p_preview_start_date - ((EXTRACT(isodow FROM p_preview_start_date)::integer - 1) * interval ''1 day''))::date)'
      );
      v_sql := replace(
        v_sql,
        '(p_preview_end_date IS NULL OR s.shift_date <= p_preview_end_date)',
        '(p_preview_end_date IS NULL OR s.shift_date <= (p_preview_end_date + ((7 - EXTRACT(isodow FROM p_preview_end_date)::integer) * interval ''1 day''))::date)'
      );
      EXECUTE v_sql;
    END IF;
  END LOOP;
END $$;
