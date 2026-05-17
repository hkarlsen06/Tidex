CREATE OR REPLACE FUNCTION public.ensure_default_job(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_id uuid;
  v_payroll_day integer;
  v_half_tax_month integer;
  v_monthly_goal integer;
  v_currency text;
  v_locale text;
  v_job_name text;
BEGIN
  SELECT j.id
  INTO v_job_id
  FROM public.jobs j
  WHERE j.user_id = p_user_id
    AND j.is_default = true
    AND j.deleted_at IS NULL
    AND j.archived_at IS NULL
  LIMIT 1;

  IF v_job_id IS NULL THEN
    SELECT
      COALESCE(us.payroll_day, 15),
      us.half_tax_month,
      COALESCE(us.monthly_goal, 20000),
      COALESCE(us.currency, 'kr')
    INTO v_payroll_day, v_half_tax_month, v_monthly_goal, v_currency
    FROM public.user_settings us
    WHERE us.user_id = p_user_id
    LIMIT 1;

    SELECT lower(replace(au.raw_user_meta_data->>'locale', '_', '-'))
    INTO v_locale
    FROM auth.users au
    WHERE au.id = p_user_id
    LIMIT 1;

    WITH localized_names(locale, name) AS (
      VALUES
        ('ar', 'وظيفة'),
        ('bg', 'Работа'),
        ('bn', 'চাকরি'),
        ('ca', 'Treball'),
        ('cs', 'Práce'),
        ('da', 'Job'),
        ('de', 'Stelle'),
        ('el', 'Δουλειά'),
        ('en', 'Job'),
        ('es', 'Trabajo'),
        ('et', 'Töö'),
        ('fa', 'شغل'),
        ('fi', 'Työ'),
        ('fil', 'Trabaho'),
        ('fr', 'Emploi'),
        ('he', 'עבודה'),
        ('hi', 'नौकरी'),
        ('hr', 'Posao'),
        ('hu', 'Munka'),
        ('id', 'Pekerjaan'),
        ('is', 'Starf'),
        ('it', 'Lavoro'),
        ('ja', '職務'),
        ('ko', '직업'),
        ('lt', 'Darbas'),
        ('lv', 'Darbs'),
        ('nb', 'Jobb'),
        ('nl', 'Baan'),
        ('nn', 'Jobb'),
        ('no', 'Jobb'),
        ('pl', 'Praca'),
        ('pt-br', 'Trabalho'),
        ('ro', 'Slujbă'),
        ('ru', 'Работа'),
        ('sk', 'Úloha'),
        ('sl', 'Delo'),
        ('sr', 'Posao'),
        ('sv', 'Jobb'),
        ('sw', 'Kazi'),
        ('ta', 'வேலை'),
        ('th', 'งาน'),
        ('tr', 'İş'),
        ('uk', 'Робота'),
        ('ur', 'نوکری'),
        ('vi', 'Công việc'),
        ('zh-hans', '工作'),
        ('zh-hant', '工作')
    )
    SELECT ln.name
    INTO v_job_name
    FROM localized_names ln
    WHERE ln.locale = v_locale
       OR ln.locale = split_part(v_locale, '-', 1)
    ORDER BY CASE WHEN ln.locale = v_locale THEN 0 ELSE 1 END
    LIMIT 1;

    INSERT INTO public.jobs (
      user_id,
      name,
      is_default,
      payroll_day,
      half_tax_month,
      monthly_goal,
      currency
    )
    VALUES (
      p_user_id,
      COALESCE(v_job_name, 'Job'),
      true,
      COALESCE(v_payroll_day, 15),
      v_half_tax_month,
      COALESCE(v_monthly_goal, 20000),
      COALESCE(v_currency, 'kr')
    )
    ON CONFLICT DO NOTHING;

    SELECT j.id
    INTO v_job_id
    FROM public.jobs j
    WHERE j.user_id = p_user_id
      AND j.is_default = true
      AND j.deleted_at IS NULL
      AND j.archived_at IS NULL
    LIMIT 1;
  END IF;

  RETURN v_job_id;
END;
$$;

WITH localized_names(locale, name) AS (
  VALUES
    ('ar', 'وظيفة'),
    ('bg', 'Работа'),
    ('bn', 'চাকরি'),
    ('ca', 'Treball'),
    ('cs', 'Práce'),
    ('da', 'Job'),
    ('de', 'Stelle'),
    ('el', 'Δουλειά'),
    ('en', 'Job'),
    ('es', 'Trabajo'),
    ('et', 'Töö'),
    ('fa', 'شغل'),
    ('fi', 'Työ'),
    ('fil', 'Trabaho'),
    ('fr', 'Emploi'),
    ('he', 'עבודה'),
    ('hi', 'नौकरी'),
    ('hr', 'Posao'),
    ('hu', 'Munka'),
    ('id', 'Pekerjaan'),
    ('is', 'Starf'),
    ('it', 'Lavoro'),
    ('ja', '職務'),
    ('ko', '직업'),
    ('lt', 'Darbas'),
    ('lv', 'Darbs'),
    ('nb', 'Jobb'),
    ('nl', 'Baan'),
    ('nn', 'Jobb'),
    ('no', 'Jobb'),
    ('pl', 'Praca'),
    ('pt-br', 'Trabalho'),
    ('ro', 'Slujbă'),
    ('ru', 'Работа'),
    ('sk', 'Úloha'),
    ('sl', 'Delo'),
    ('sr', 'Posao'),
    ('sv', 'Jobb'),
    ('sw', 'Kazi'),
    ('ta', 'வேலை'),
    ('th', 'งาน'),
    ('tr', 'İş'),
    ('uk', 'Робота'),
    ('ur', 'نوکری'),
    ('vi', 'Công việc'),
    ('zh-hans', '工作'),
    ('zh-hant', '工作')
),
candidate_jobs AS (
  SELECT
    j.id,
    COALESCE(exact_locale.name, base_locale.name, 'Job') AS localized_name
  FROM public.jobs j
  JOIN auth.users au ON au.id = j.user_id
  LEFT JOIN localized_names exact_locale
    ON exact_locale.locale = lower(replace(au.raw_user_meta_data->>'locale', '_', '-'))
  LEFT JOIN localized_names base_locale
    ON base_locale.locale = split_part(
      lower(replace(au.raw_user_meta_data->>'locale', '_', '-')),
      '-',
      1
    )
  WHERE j.name = 'Job'
    AND j.is_default = true
    AND j.deleted_at IS NULL
)
UPDATE public.jobs j
SET name = c.localized_name
FROM candidate_jobs c
WHERE j.id = c.id
  AND j.name IS DISTINCT FROM c.localized_name;

-- Verification scenarios:
-- 1. A default, non-deleted job named exactly 'Job' with locale nb/nn/no becomes 'Jobb'.
-- 2. A default, non-deleted job named exactly 'Job' with locale en or an unknown locale remains 'Job'.
-- 3. Jobs named 'Jobb' or any user-entered value are untouched because the backfill only matches name = 'Job'.
