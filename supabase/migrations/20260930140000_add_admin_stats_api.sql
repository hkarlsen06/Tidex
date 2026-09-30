-- Adds public.admin_get_stats_api and its helpers for the admin Stats screen.
-- Source: supabase/sql/functions/admin/admin_get_stats_api.sql

-- Numbers for the admin Stats screen, grouped into titled sections that the app draws as they
-- come. Every item has a kind, an optional title, and "collapsed" when the app should show it
-- as a row that expands. The kinds are:
--   tiles    headline numbers: {tiles: [{label, value, caption, progress}]}, progress is 0 to 1
--   series   weekly counts, oldest first: {points: [{date, value}]}
--   bars     a breakdown: {rows: [{label, value}], total}. Without total, each row is a share
--            of the sum. With total, rows can overlap, as when counting features in use.
--   funnel   steps in order, each a share of the first: {rows: [{label, value}]}
--   list     label and value rows: {rows: [{label, value, detail}]}
--   cohorts  sign-up months: {rows: [{label, total, logged, active}]}

-- "43%", or a dash when there is nothing to divide by.
CREATE OR REPLACE FUNCTION internal.admin_percent(p_part bigint, p_whole bigint)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN COALESCE(p_whole, 0) = 0 THEN '–'
    ELSE round(100.0 * p_part / p_whole)::int || '%'
  END;
$function$;

-- Counts per week for the last p_weeks weeks, oldest first. Weeks start on Monday in p_time_zone.
CREATE OR REPLACE FUNCTION internal.admin_weekly_counts(
  p_times timestamptz[],
  p_time_zone text,
  p_weeks integer
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO ''
AS $function$
  WITH weeks AS (
    SELECT (date_trunc('week', now() AT TIME ZONE p_time_zone)::date - 7 * i) AS week
    FROM generate_series(0, p_weeks - 1) AS i
  ),
  counts AS (
    SELECT date_trunc('week', t AT TIME ZONE p_time_zone)::date AS week, count(*) AS n
    FROM unnest(p_times) AS t
    GROUP BY 1
  )
  SELECT jsonb_agg(
    jsonb_build_object('date', w.week, 'value', COALESCE(c.n, 0))
    ORDER BY w.week
  )
  FROM weeks w
  LEFT JOIN counts c USING (week);
$function$;

-- A bars item that counts each label. The eight largest get their own row and the rest
-- go into "Other". Missing labels count as "Unknown".
CREATE OR REPLACE FUNCTION internal.admin_breakdown(p_title text, p_labels text[])
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  WITH counted AS (
    SELECT COALESCE(NULLIF(label, ''), 'Unknown') AS label, count(*) AS n
    FROM unnest(p_labels) AS label
    GROUP BY 1
  ),
  ranked AS (
    SELECT label, n, row_number() OVER (ORDER BY n DESC, label) AS position
    FROM counted
  ),
  grouped AS (
    SELECT CASE WHEN position <= 8 THEN label ELSE 'Other' END AS label, sum(n) AS n
    FROM ranked
    GROUP BY 1
  )
  SELECT jsonb_build_object(
    'kind', 'bars',
    'title', p_title,
    'rows', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object('label', label, 'value', n)
          ORDER BY label = 'Other', n DESC, label
        )
        FROM grouped
      ),
      '[]'::jsonb
    )
  );
$function$;

REVOKE ALL ON FUNCTION internal.admin_percent(bigint, bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION internal.admin_weekly_counts(timestamptz[], text, integer)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION internal.admin_breakdown(text, text[]) FROM PUBLIC, anon, authenticated;


CREATE OR REPLACE FUNCTION public.admin_get_stats_api(p_time_zone text DEFAULT 'Europe/Oslo')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_month_start date;
  v_accounts bigint;
  v_active_7 bigint;
  v_active_30 uuid[];
  v_openers uuid[];
  v_users jsonb;
  v_before_signup jsonb;
  v_setup jsonb;
  v_activation jsonb;
  v_shifts jsonb;
  v_friends jsonb;
  v_app jsonb;
  v_sign_in jsonb;
BEGIN
  PERFORM public.assert_is_admin();

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_time_zone) THEN
    RAISE EXCEPTION 'Unknown time zone %', p_time_zone;
  END IF;

  v_month_start := date_trunc('month', now() AT TIME ZONE p_time_zone)::date;
  SELECT count(*) INTO v_accounts FROM auth.users;

  -- Active uses the same last-active time as the admin users list.
  SELECT
    count(*) FILTER (WHERE a.last_active >= now() - interval '7 days'),
    COALESCE(array_agg(a.id) FILTER (WHERE a.last_active >= now() - interval '30 days'), '{}')
  INTO v_active_7, v_active_30
  FROM (SELECT u.id, internal.admin_user_last_active(u.id) AS last_active FROM auth.users u) a;

  -- People whose latest recorded app open is in the last 30 days.
  SELECT COALESCE(array_agg(user_id), '{}')
  INTO v_openers
  FROM internal.user_app_activity
  WHERE last_active_at >= now() - interval '30 days';

  -- Users

  v_users := jsonb_build_object(
    'title', 'Users',
    'items', jsonb_build_array(
      jsonb_build_object('kind', 'tiles', 'tiles', jsonb_build_array(
        jsonb_build_object('label', 'Accounts', 'value', v_accounts::text),
        jsonb_build_object(
          'label', 'New in 30 days',
          'value', (SELECT count(*) FROM auth.users WHERE created_at >= now() - interval '30 days')::text
        ),
        jsonb_build_object('label', 'Active in 7 days', 'value', v_active_7::text),
        jsonb_build_object('label', 'Active in 30 days', 'value', cardinality(v_active_30)::text)
      )),
      jsonb_build_object(
        'kind', 'series',
        'title', 'New accounts per week',
        'points', internal.admin_weekly_counts(ARRAY(SELECT created_at FROM auth.users), p_time_zone, 26)
      ),
      internal.admin_breakdown('Sign-in method', ARRAY(
        SELECT CASE raw_app_meta_data ->> 'provider'
          WHEN 'apple' THEN 'Apple'
          WHEN 'google' THEN 'Google'
          WHEN 'email' THEN 'Email'
          WHEN 'phone' THEN 'Phone'
          ELSE raw_app_meta_data ->> 'provider'
        END
        FROM auth.users
      ))
    )
  );

  -- Before sign-up: installs that first saw the welcome screen in the last 30 days, and how
  -- many of those installs reached each later step.

  WITH cohort AS (
    SELECT install_id
    FROM internal.onboarding_preauth_steps
    WHERE step = 'welcome' AND reached_at >= now() - interval '30 days'
  ),
  steps AS (
    SELECT p.step, count(*) AS n
    FROM internal.onboarding_preauth_steps p
    JOIN cohort USING (install_id)
    GROUP BY p.step
  )
  SELECT jsonb_build_object(
    'title', 'Before sign-up',
    'items', jsonb_build_array(
      jsonb_build_object('kind', 'funnel', 'title', 'Installs in the last 30 days', 'rows', jsonb_build_array(
        jsonb_build_object('label', 'Saw the welcome screen',
          'value', COALESCE((SELECT n FROM steps WHERE step = 'welcome'), 0)),
        jsonb_build_object('label', 'Opened the demo',
          'value', COALESCE((SELECT n FROM steps WHERE step = 'add_shift_simulator'), 0)),
        jsonb_build_object('label', 'Added a demo shift',
          'value', COALESCE((SELECT n FROM steps WHERE step = 'demo_shift_added'), 0)),
        jsonb_build_object('label', 'Reached sign-up',
          'value', COALESCE((SELECT n FROM steps WHERE step = 'signup_screen'), 0))
      )),
      jsonb_build_object('kind', 'list', 'rows', jsonb_build_array(
        jsonb_build_object('label', 'Went to log in',
          'value', COALESCE((SELECT n FROM steps WHERE step = 'login_screen'), 0)::text)
      ))
    )
  )
  INTO v_before_signup;

  -- Setup after sign-up

  WITH steps AS (
    SELECT step, count(*) AS n FROM public.onboarding_funnel_steps GROUP BY step
  )
  SELECT jsonb_build_object(
    'title', 'Setup after sign-up',
    'items', jsonb_build_array(
      jsonb_build_object('kind', 'funnel', 'title', 'Setup', 'rows', (
        SELECT jsonb_agg(
          jsonb_build_object('label', s.label, 'value', COALESCE(steps.n, 0)) ORDER BY s.position
        )
        FROM (VALUES
          (1, 'postauth_purpose', 'Purpose'),
          (2, 'postauth_wage', 'Wage'),
          (3, 'postauth_supplements', 'Supplements'),
          (4, 'postauth_jobBasics', 'Job'),
          (5, 'postauth_settingsAccordion', 'Settings'),
          (6, 'onboarding_completed', 'Finished setup'),
          (7, 'first_shift_added', 'Added a first shift')
        ) AS s(position, step, label)
        LEFT JOIN steps USING (step)
      )),
      internal.admin_breakdown('First shift added with', ARRAY(
        SELECT CASE replace(step, 'first_shift_via_', '')
          WHEN 'manual' THEN 'Add screen'
          WHEN 'recurring' THEN 'Recurring schedule'
          WHEN 'clock' THEN 'Clock in'
          WHEN 'calendar_import' THEN 'Calendar import'
          ELSE replace(step, 'first_shift_via_', '')
        END
        FROM public.onboarding_funnel_steps
        WHERE step LIKE 'first\_shift\_via\_%'
      )),
      jsonb_build_object('kind', 'list', 'rows', jsonb_build_array(
        jsonb_build_object('label', 'Started from the demo shift',
          'value', COALESCE((SELECT n FROM steps WHERE step = 'demo_shift_prefilled'), 0)::text)
      ))
    )
  )
  INTO v_setup;

  -- Activation. A first shift is a single shift or a recurring schedule.

  WITH accounts AS (
    SELECT
      u.id,
      u.created_at,
      LEAST(
        (SELECT min(s.created_at) FROM public.user_shifts s WHERE s.user_id = u.id),
        (SELECT min(r.created_at) FROM public.recurring_shifts r WHERE r.user_id = u.id)
      ) AS first_shift_at,
      u.id = ANY (v_active_30) AS is_active
    FROM auth.users u
  ),
  -- Old enough to have had a first week.
  recent AS (
    SELECT * FROM accounts
    WHERE created_at >= now() - interval '97 days' AND created_at < now() - interval '7 days'
  ),
  -- Old enough that being active means they came back.
  settled AS (
    SELECT * FROM accounts
    WHERE created_at >= now() - interval '120 days' AND created_at < now() - interval '30 days'
  ),
  cohorts AS (
    SELECT
      date_trunc('month', created_at AT TIME ZONE p_time_zone)::date AS month,
      count(*) AS total,
      count(*) FILTER (WHERE first_shift_at IS NOT NULL) AS logged,
      count(*) FILTER (WHERE is_active) AS active
    FROM accounts
    WHERE created_at >= (v_month_start - interval '5 months') AT TIME ZONE p_time_zone
    GROUP BY 1
  ),
  totals AS (
    SELECT
      (SELECT count(*) FROM recent) AS recent,
      (SELECT count(*) FROM recent WHERE first_shift_at < created_at + interval '1 day') AS day_one,
      (SELECT count(*) FROM recent WHERE first_shift_at < created_at + interval '7 days') AS first_week,
      (SELECT count(*) FROM settled) AS settled,
      (SELECT count(*) FROM settled WHERE is_active) AS returned
  )
  SELECT jsonb_build_object(
    'title', 'Activation',
    'items', jsonb_build_array(
      jsonb_build_object('kind', 'tiles', 'tiles', jsonb_build_array(
        jsonb_build_object(
          'label', 'Shift on day one',
          'value', internal.admin_percent(t.day_one, t.recent),
          'caption', 'of ' || t.recent || ' new accounts',
          'progress', CASE WHEN t.recent > 0 THEN t.day_one::numeric / t.recent END
        ),
        jsonb_build_object(
          'label', 'Shift in week one',
          'value', internal.admin_percent(t.first_week, t.recent),
          'caption', 'of ' || t.recent || ' new accounts',
          'progress', CASE WHEN t.recent > 0 THEN t.first_week::numeric / t.recent END
        ),
        jsonb_build_object(
          'label', 'Came back',
          'value', internal.admin_percent(t.returned, t.settled),
          'caption', 'after 30+ days',
          'progress', CASE WHEN t.settled > 0 THEN t.returned::numeric / t.settled END
        )
      )),
      jsonb_build_object('kind', 'cohorts', 'title', 'By sign-up month', 'rows', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'label', to_char(month, 'Mon'),
            'total', total,
            'logged', logged,
            'active', active
          )
          ORDER BY month
        )
        FROM cohorts
      ), '[]'::jsonb))
    )
  )
  INTO v_activation
  FROM totals t;

  -- Shifts and pay

  WITH latest_wage AS (
    SELECT DISTINCT ON (w.user_id) w.user_id, w.tariff_type_id, w.tax_enabled
    FROM public.wage_snapshots w
    WHERE w.deleted_at IS NULL
    ORDER BY w.user_id, w.from_date DESC NULLS LAST, w.created_at DESC
  )
  SELECT jsonb_build_object(
    'title', 'Shifts and pay',
    'items', jsonb_build_array(
      jsonb_build_object('kind', 'tiles', 'tiles', jsonb_build_array(
        jsonb_build_object(
          'label', 'Shifts added',
          'value', (SELECT count(*) FROM public.user_shifts WHERE created_at >= now() - interval '30 days')::text,
          'caption', 'last 30 days'
        ),
        jsonb_build_object(
          'label', 'People adding',
          'value', (
            SELECT count(DISTINCT user_id) FROM public.user_shifts
            WHERE created_at >= now() - interval '30 days'
          )::text,
          'caption', 'last 30 days'
        ),
        jsonb_build_object(
          'label', 'Shifts saved',
          'value', (SELECT count(*) FROM public.user_shifts WHERE deleted_at IS NULL)::text,
          'caption', 'in total'
        )
      )),
      jsonb_build_object(
        'kind', 'series',
        'title', 'Shifts added per week',
        'points', internal.admin_weekly_counts(ARRAY(SELECT created_at FROM public.user_shifts), p_time_zone, 26)
      ),
      jsonb_build_object(
        'kind', 'series',
        'title', 'People adding shifts per week',
        'collapsed', true,
        'points', internal.admin_weekly_counts(
          ARRAY(
            SELECT min(created_at) FROM public.user_shifts
            GROUP BY user_id, date_trunc('week', created_at AT TIME ZONE p_time_zone)
          ),
          p_time_zone,
          26
        )
      ),
      internal.admin_breakdown('Pay setup', ARRAY(
        SELECT CASE WHEN tariff_type_id IS NOT NULL THEN 'Tariff' ELSE 'Own hourly wage' END
        FROM latest_wage
      )),
      internal.admin_breakdown('Tax deduction', ARRAY(
        SELECT CASE WHEN tax_enabled THEN 'On' ELSE 'Off' END FROM latest_wage
      )),
      jsonb_build_object(
        'kind', 'bars',
        'title', 'Features in use',
        'total', v_accounts,
        'rows', (
          SELECT jsonb_agg(jsonb_build_object('label', label, 'value', n) ORDER BY n DESC, label)
          FROM (VALUES
            ('Shift reminders', (
              SELECT count(*) FROM public.notification_preferences WHERE shift_reminders_enabled)),
            ('Friend shift alerts', (
              SELECT count(*) FROM public.notification_preferences WHERE shared_shifts_enabled)),
            ('More than one job', (
              SELECT count(*) FROM (
                SELECT user_id FROM public.jobs
                WHERE deleted_at IS NULL AND archived_at IS NULL
                GROUP BY user_id HAVING count(*) > 1
              ) j)),
            ('Pay adjustments', (
              SELECT count(DISTINCT user_id) FROM public.payroll_adjustments WHERE deleted_at IS NULL)),
            ('Recurring schedules', (
              SELECT count(DISTINCT user_id) FROM public.recurring_shifts WHERE deleted_at IS NULL)),
            ('Calendar events', (
              SELECT count(DISTINCT user_id) FROM public.events WHERE deleted_at IS NULL)),
            ('Calendar feed', (
              SELECT count(DISTINCT user_id) FROM internal.calendar_subscription_tokens
              WHERE revoked_at IS NULL))
          ) AS f(label, n)
        )
      ),
      internal.admin_breakdown('Currency', ARRAY(SELECT currency FROM public.user_settings))
        || '{"collapsed": true}'::jsonb
    )
  )
  INTO v_shifts;

  -- Friends. Shares blocked by either person are left out.

  v_friends := jsonb_build_object(
    'title', 'Friends',
    'items', jsonb_build_array(
      jsonb_build_object('kind', 'tiles', 'tiles', jsonb_build_array(
        jsonb_build_object('label', 'Shares', 'value', (
          SELECT count(*) FROM public.shift_shares WHERE blocked_by_user_id IS NULL)::text),
        jsonb_build_object('label', 'People sharing', 'value', (
          SELECT count(DISTINCT owner_id) FROM public.shift_shares WHERE blocked_by_user_id IS NULL)::text),
        jsonb_build_object(
          'label', 'Messages',
          'value', (SELECT count(*) FROM public.messages WHERE created_at >= now() - interval '30 days')::text,
          'caption', 'last 30 days'
        )
      )),
      jsonb_build_object(
        'kind', 'series',
        'title', 'Messages per week',
        'points', internal.admin_weekly_counts(ARRAY(SELECT created_at FROM public.messages), p_time_zone, 26)
      ),
      jsonb_build_object('kind', 'list', 'rows', jsonb_build_array(
        jsonb_build_object('label', 'People messaging in 30 days', 'value', (
          SELECT count(DISTINCT sender_user_id) FROM public.messages
          WHERE created_at >= now() - interval '30 days')::text),
        jsonb_build_object('label', 'Chats', 'value', (SELECT count(*) FROM public.threads)::text)
      ))
    )
  );

  -- App and devices. App version comes from push registrations. The rest comes from each
  -- person's latest recorded app open in the last 30 days.

  WITH openers AS (
    SELECT * FROM internal.user_app_activity WHERE user_id = ANY (v_openers)
  ),
  latest_device AS (
    SELECT DISTINCT ON (user_id) user_id, app_version
    FROM internal.push_devices
    WHERE COALESCE(last_seen_at, updated_at) >= now() - interval '30 days'
    ORDER BY user_id, COALESCE(last_seen_at, updated_at) DESC
  ),
  push AS (
    SELECT
      (SELECT count(DISTINCT user_id) FROM internal.push_devices WHERE apns_token IS NOT NULL) AS accounts,
      (
        SELECT count(DISTINCT d.user_id) FROM internal.push_devices d
        WHERE d.apns_token IS NOT NULL AND d.user_id = ANY (v_active_30)
      ) AS active
  )
  SELECT jsonb_build_object(
    'title', 'App and devices',
    'items', jsonb_build_array(
      jsonb_build_object('kind', 'tiles', 'tiles', jsonb_build_array(
        jsonb_build_object(
          'label', 'Accounts with a push token',
          'value', internal.admin_percent(p.accounts, v_accounts),
          'caption', p.accounts || ' of ' || v_accounts,
          'progress', CASE WHEN v_accounts > 0 THEN p.accounts::numeric / v_accounts END
        ),
        jsonb_build_object(
          'label', 'Active people with a push token',
          'value', internal.admin_percent(p.active, cardinality(v_active_30)),
          'caption', p.active || ' of ' || cardinality(v_active_30) || ' active in 30 days',
          'progress', CASE WHEN cardinality(v_active_30) > 0
            THEN p.active::numeric / cardinality(v_active_30) END
        )
      )),
      internal.admin_breakdown('App version', ARRAY(SELECT app_version FROM latest_device)),
      internal.admin_breakdown('iOS version', ARRAY(
        SELECT substring(os_version FROM '^iOS [0-9]+') FROM openers)) || '{"collapsed": true}'::jsonb,
      internal.admin_breakdown('Device', ARRAY(SELECT device_model FROM openers))
        || '{"collapsed": true}'::jsonb,
      internal.admin_breakdown('App language', ARRAY(SELECT app_language FROM openers))
        || '{"collapsed": true}'::jsonb,
      internal.admin_breakdown('Notifications', ARRAY(
        SELECT CASE notification_permission
          WHEN 'authorized' THEN 'Allowed'
          WHEN 'denied' THEN 'Denied'
          WHEN 'not_determined' THEN 'Not asked yet'
          WHEN 'provisional' THEN 'Provisional'
          WHEN 'ephemeral' THEN 'Ephemeral'
          ELSE notification_permission
        END
        FROM openers
      )) || '{"collapsed": true}'::jsonb,
      internal.admin_breakdown('Background refresh', ARRAY(
        SELECT CASE background_refresh
          WHEN 'available' THEN 'On'
          WHEN 'denied' THEN 'Off'
          WHEN 'restricted' THEN 'Restricted'
          ELSE background_refresh
        END
        FROM openers
      )) || '{"collapsed": true}'::jsonb,
      internal.admin_breakdown('Widgets', ARRAY(
        SELECT regexp_replace(kind, 'Widget$', '')
        FROM openers, unnest(widget_kinds) AS kind
        UNION ALL
        SELECT 'None' FROM openers WHERE COALESCE(cardinality(widget_kinds), 0) = 0
      )) || jsonb_build_object('collapsed', true, 'total', cardinality(v_openers)),
      internal.admin_breakdown('Appearance', ARRAY(
        SELECT CASE appearance WHEN 'light' THEN 'Light' WHEN 'dark' THEN 'Dark' ELSE appearance END
        FROM openers
      )) || '{"collapsed": true}'::jsonb,
      internal.admin_breakdown('Text size', ARRAY(SELECT text_size FROM openers))
        || '{"collapsed": true}'::jsonb,
      internal.admin_breakdown('Reduce Motion', ARRAY(
        SELECT CASE reduce_motion WHEN true THEN 'On' WHEN false THEN 'Off' END FROM openers
      )) || '{"collapsed": true}'::jsonb
    )
  )
  INTO v_app
  FROM push p;

  -- Sign-in health: warnings and errors from the sign-in diagnostics, last 7 days.

  WITH problems AS (
    SELECT * FROM internal.auth_diagnostic_events
    WHERE occurred_at >= now() - interval '7 days' AND severity IN ('warning', 'error')
  )
  SELECT jsonb_build_object(
    'title', 'Sign-in problems',
    'items', jsonb_build_array(
      jsonb_build_object('kind', 'tiles', 'tiles', jsonb_build_array(
        jsonb_build_object('label', 'Warnings and errors', 'value', (SELECT count(*) FROM problems)::text,
          'caption', 'last 7 days'),
        jsonb_build_object('label', 'Installs', 'value', (
          SELECT count(DISTINCT metadata ->> 'install_id') FROM problems)::text),
        jsonb_build_object('label', 'Signed-in people', 'value', (
          SELECT count(DISTINCT user_id) FROM problems)::text)
      )),
      internal.admin_breakdown('By event', ARRAY(
        SELECT replace(event_type, '_', ' ') || CASE WHEN severity = 'error' THEN ' (error)' ELSE '' END
        FROM problems
      )) || '{"collapsed": true}'::jsonb
    )
  )
  INTO v_sign_in;

  RETURN jsonb_build_object(
    'generatedAt', now(),
    'sections', jsonb_build_array(
      v_users, v_before_signup, v_setup, v_activation, v_shifts, v_friends, v_app, v_sign_in
    )
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_stats_api(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_stats_api(text) TO authenticated;
