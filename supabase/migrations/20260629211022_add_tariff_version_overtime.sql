DO $$
DECLARE
  v_disabled_overtime jsonb := '{
    "enabled": false,
    "weeklyThresholdHours": 40,
    "rules": []
  }'::jsonb;
  v_hk_retail_overtime jsonb := '{
    "enabled": true,
    "weeklyThresholdHours": 37.5,
    "rules": [
      { "days": [1, 2, 3, 4, 5, 6], "appliesOnHolidays": false, "from": "00:00", "to": "08:00", "percent": 100 },
      { "days": [1, 2, 3, 4, 5, 6], "appliesOnHolidays": false, "from": "08:00", "to": "21:00", "percent": 50 },
      { "days": [1, 2, 3, 4, 5, 6], "appliesOnHolidays": false, "from": "21:00", "to": "24:00", "percent": 100 },
      { "days": [7], "appliesOnHolidays": true, "from": "00:00", "to": "24:00", "percent": 100 },
      { "days": [1, 2, 3, 4, 5, 6, 7], "appliesOnHolidays": true, "from": "00:00", "to": "24:00", "percent": 100 }
    ]
  }'::jsonb;
  v_allmenngjort_overtime jsonb := '{
    "enabled": true,
    "weeklyThresholdHours": 40,
    "rules": [
      { "days": [1, 2, 3, 4, 5, 6, 7], "appliesOnHolidays": false, "from": "00:00", "to": "24:00", "percent": 40 },
      { "days": [1, 2, 3, 4, 5, 6, 7], "appliesOnHolidays": true, "from": "00:00", "to": "24:00", "percent": 40 }
    ]
  }'::jsonb;
  v_riksavtalen_overtime jsonb := '{
    "enabled": true,
    "weeklyThresholdHours": 37.5,
    "rules": [
      { "days": [1, 2, 3, 4, 5, 6], "appliesOnHolidays": false, "from": "00:00", "to": "06:00", "percent": 100 },
      { "days": [1, 2, 3, 4, 5, 6], "appliesOnHolidays": false, "from": "06:00", "to": "21:00", "percent": 50 },
      { "days": [1, 2, 3, 4, 5, 6], "appliesOnHolidays": false, "from": "21:00", "to": "24:00", "percent": 100 },
      { "days": [7], "appliesOnHolidays": true, "from": "00:00", "to": "24:00", "percent": 100 },
      { "days": [1, 2, 3, 4, 5, 6, 7], "appliesOnHolidays": true, "from": "00:00", "to": "24:00", "percent": 100 }
    ]
  }'::jsonb;
  v_vekter_overtime jsonb := '{
    "enabled": true,
    "weeklyThresholdHours": 37.5,
    "rules": [
      { "days": [1, 2, 3, 4, 5], "appliesOnHolidays": false, "from": "00:00", "to": "06:00", "percent": 100 },
      { "days": [1, 2, 3, 4, 5], "appliesOnHolidays": false, "from": "06:00", "to": "21:00", "percent": 50 },
      { "days": [1, 2, 3, 4, 5], "appliesOnHolidays": false, "from": "21:00", "to": "24:00", "percent": 100 },
      { "days": [6], "appliesOnHolidays": false, "from": "00:00", "to": "06:00", "percent": 100 },
      { "days": [6], "appliesOnHolidays": false, "from": "06:00", "to": "12:00", "percent": 50 },
      { "days": [6], "appliesOnHolidays": false, "from": "12:00", "to": "24:00", "percent": 100 },
      { "days": [7], "appliesOnHolidays": true, "from": "00:00", "to": "24:00", "percent": 100 },
      { "days": [1, 2, 3, 4, 5, 6, 7], "appliesOnHolidays": true, "from": "00:00", "to": "24:00", "percent": 100 }
    ]
  }'::jsonb;
BEGIN
  ALTER TABLE internal.tariff_versions
    ADD COLUMN IF NOT EXISTS overtime jsonb;

  UPDATE internal.tariff_versions
  SET overtime = CASE tariff_type_id
    WHEN 'bygg_allmenngjort' THEN v_allmenngjort_overtime
    WHEN 'renhold_allmenngjort' THEN v_allmenngjort_overtime
    WHEN 'riksavtalen_hotel' THEN v_riksavtalen_overtime
    WHEN 'vekteroverenskomst' THEN v_vekter_overtime
    ELSE v_hk_retail_overtime
  END
  WHERE overtime IS NULL;

  COMMENT ON COLUMN internal.tariff_versions.overtime IS
    'Default overtime configuration for wage snapshots created from this tariff version.';

  UPDATE public.wage_snapshots AS w
  SET overtime = COALESCE(
    (
      SELECT tv.overtime
      FROM internal.tariff_versions AS tv
      WHERE tv.tariff_type_id = w.tariff_type_id
        AND (w.from_date IS NULL OR tv.effective_date <= w.from_date)
      ORDER BY tv.effective_date DESC
      LIMIT 1
    ),
    CASE w.tariff_type_id
      WHEN 'bygg_allmenngjort' THEN v_allmenngjort_overtime
      WHEN 'renhold_allmenngjort' THEN v_allmenngjort_overtime
      WHEN 'riksavtalen_hotel' THEN v_riksavtalen_overtime
      WHEN 'vekteroverenskomst' THEN v_vekter_overtime
      ELSE v_hk_retail_overtime
    END
  )
  WHERE w.tariff_type_id IS NOT NULL
    AND COALESCE(w.overtime, v_disabled_overtime) = v_disabled_overtime;
END $$;

ALTER TABLE internal.tariff_versions
  ALTER COLUMN overtime SET DEFAULT '{
    "enabled": false,
    "weeklyThresholdHours": 40,
    "rules": []
  }'::jsonb,
  ALTER COLUMN overtime SET NOT NULL;

DROP FUNCTION IF EXISTS public.get_tariff_version_for_date(text, date);
DROP FUNCTION IF EXISTS public.get_tariff_versions(text);

CREATE OR REPLACE FUNCTION public.get_tariff_version_for_date(
  p_tariff_type text,
  p_target_date date
)
RETURNS TABLE (
  id uuid,
  tariff_type_id text,
  effective_date date,
  name text,
  rates jsonb,
  supplements jsonb,
  overtime jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT id, tariff_type_id, effective_date, name, rates, supplements, overtime
  FROM internal.tariff_versions
  WHERE tariff_type_id = p_tariff_type
    AND effective_date <= p_target_date
  ORDER BY effective_date DESC
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.get_tariff_versions(
  p_tariff_type text DEFAULT 'hk_retail'::text
)
RETURNS TABLE (
  id uuid,
  tariff_type_id text,
  effective_date date,
  name text,
  rates jsonb,
  supplements jsonb,
  overtime jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT id, tariff_type_id, effective_date, name, rates, supplements, overtime
  FROM internal.tariff_versions
  WHERE tariff_type_id = p_tariff_type
  ORDER BY effective_date DESC;
$function$;

REVOKE ALL ON FUNCTION public.get_tariff_version_for_date(text, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_tariff_versions(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_tariff_version_for_date(text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_tariff_versions(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_tariff_version_for_date(text, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_tariff_versions(text) TO service_role;
