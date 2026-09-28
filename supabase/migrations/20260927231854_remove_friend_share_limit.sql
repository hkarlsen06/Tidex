-- Tidex is free, so sharing has no friend limit. get_friends_tab_bootstrap keeps
-- returning capacity for older app builds; canAdd true with limit 0 hides their
-- quota UI.

CREATE OR REPLACE FUNCTION public.manage_sharing_action(p_action text, p_identifier text DEFAULT NULL::text, p_recipient_id uuid DEFAULT NULL::uuid, p_show_earnings boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_target_id uuid;
  v_normalized text;
  v_identifier text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;



  IF p_action = 'createShare' THEN
    IF p_identifier IS NULL OR btrim(p_identifier) = '' THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Vennligst oppgi en gyldig e-post, telefonnummer eller brukernavn'
      );
    END IF;

    v_identifier := btrim(p_identifier);

    IF position('@' IN v_identifier) > 0 AND left(v_identifier, 1) <> '@' THEN
      SELECT id INTO v_target_id
      FROM auth.users
      WHERE lower(email) = lower(v_identifier)
      LIMIT 1;
    ELSE
      v_identifier := lower(v_identifier);
      IF left(v_identifier, 1) = '@' THEN
        v_identifier := substr(v_identifier, 2);
      END IF;

      SELECT id INTO v_target_id
      FROM public.profiles
      WHERE username = v_identifier
      LIMIT 1;

      IF v_target_id IS NULL THEN
        v_normalized := regexp_replace(p_identifier, '\D', '', 'g');
        IF length(v_normalized) = 8 THEN
          v_normalized := '47' || v_normalized;
        ELSIF left(v_normalized, 2) = '00' THEN
          v_normalized := substr(v_normalized, 3);
        END IF;

        SELECT id INTO v_target_id
        FROM auth.users
        WHERE phone = v_normalized
        LIMIT 1;
      END IF;
    END IF;
  ELSIF p_action = 'shareBack' THEN
    v_target_id := p_recipient_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Ugyldig handling');
  END IF;

  IF v_target_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Fant ingen bruker med denne e-posten, telefonnummeret eller brukernavnet'
    );
  END IF;

  IF v_target_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du kan ikke dele med deg selv');
  END IF;

  -- A block lives on the pair's shift_shares rows. Refuse a new share in
  -- either direction while one exists.
  IF EXISTS (
    SELECT 1
    FROM public.shift_shares
    WHERE (
      (owner_id = v_user_id AND viewer_id = v_target_id)
      OR (owner_id = v_target_id AND viewer_id = v_user_id)
    )
      AND blocked_by_user_id IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du kan ikke dele vaktene dine med denne brukeren');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.shift_shares
    WHERE owner_id = v_user_id
      AND viewer_id = v_target_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du deler allerede vaktene dine med denne brukeren');
  END IF;

  INSERT INTO public.shift_shares (
    owner_id,
    viewer_id,
    show_earnings,
    muted,
    owner_muted
  ) VALUES (
    v_user_id,
    v_target_id,
    COALESCE(p_show_earnings, false),
    false,
    false
  );

  RETURN jsonb_build_object('success', true);
END;
$function$

;

CREATE OR REPLACE FUNCTION public.get_friends_tab_bootstrap(p_preview_start_date date DEFAULT NULL::date, p_preview_end_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;



  RETURN (
    WITH incoming_shares AS (
      SELECT owner_id, created_at, show_earnings, hidden, muted, blocked_by_user_id
      FROM public.shift_shares
      WHERE viewer_id = v_user_id
    ),
    outgoing_shares AS (
      SELECT viewer_id, created_at, show_earnings, owner_muted, blocked_by_user_id
      FROM public.shift_shares
      WHERE owner_id = v_user_id
    ),
    all_user_ids AS (
      SELECT owner_id AS user_id FROM incoming_shares
      UNION
      SELECT viewer_id AS user_id FROM outgoing_shares
    ),
    user_profiles AS (
      SELECT
        u.id,
        u.email,
        u.phone,
        p.username,
        COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name') AS first_name,
        COALESCE(u.raw_user_meta_data->>'avatar_url', u.raw_user_meta_data->>'picture') AS oauth_avatar_url,
        us.profile_picture_url
      FROM auth.users u
      JOIN all_user_ids ids ON ids.user_id = u.id
      LEFT JOIN public.user_settings us ON us.user_id = u.id
      LEFT JOIN public.profiles p ON p.id = u.id
    ),
    combined AS (
      SELECT
        p.id,
        p.email,
        p.phone,
        p.username,
        p.first_name,
        p.profile_picture_url,
        p.oauth_avatar_url,
        i.created_at AS incoming_created_at,
        i.show_earnings AS incoming_show_earnings,
        i.hidden AS incoming_hidden,
        i.muted AS incoming_muted,
        i.blocked_by_user_id AS incoming_blocked_by_user_id,
        o.created_at AS outgoing_created_at,
        o.show_earnings AS outgoing_show_earnings,
        o.owner_muted AS outgoing_owner_muted,
        o.blocked_by_user_id AS outgoing_blocked_by_user_id
      FROM user_profiles p
      LEFT JOIN incoming_shares i ON i.owner_id = p.id
      LEFT JOIN outgoing_shares o ON o.viewer_id = p.id
    ),
    friend_rows AS (
      SELECT
        id,
        jsonb_build_object(
          'id', id,
          'email', email,
          'phone', phone,
          'username', username,
          'firstName', first_name,
          'profilePictureUrl', profile_picture_url,
          'oauthAvatarUrl', oauth_avatar_url,
          'sharesWithMe',
            CASE WHEN incoming_created_at IS NULL THEN NULL ELSE jsonb_build_object(
              'hidden', COALESCE(incoming_hidden, false),
              'showEarningsToMe', COALESCE(incoming_show_earnings, false),
              'sharedAt', incoming_created_at,
              'notificationFrequency', CASE WHEN COALESCE(incoming_muted, false) THEN 'muted' ELSE 'instant' END
            ) END,
          'iShareWith',
            CASE WHEN outgoing_created_at IS NULL THEN NULL ELSE jsonb_build_object(
              'showEarningsToThem', COALESCE(outgoing_show_earnings, false),
              'sharedAt', outgoing_created_at,
              'ownerMuted', COALESCE(outgoing_owner_muted, false)
            ) END
        ) AS friend_json,
        COALESCE(incoming_blocked_by_user_id, outgoing_blocked_by_user_id) AS blocked_by_user_id,
        lower(COALESCE(first_name, username, email, phone, '')) AS sort_name
      FROM combined
    ),
    visible_friends AS (
      SELECT friend_json, sort_name
      FROM friend_rows
      WHERE blocked_by_user_id IS NULL
    ),
    blocked_friends AS (
      SELECT friend_json, sort_name
      FROM friend_rows
      WHERE blocked_by_user_id = v_user_id
    ),
    outgoing_count AS (
      SELECT COUNT(*)::integer AS count
      FROM outgoing_shares
    ),
    sharer_rows AS (
      SELECT
        jsonb_build_object(
          'id', ss.owner_id,
          'email', p.email,
          'phone', p.phone,
          'username', p.username,
          'firstName', p.first_name,
          'profilePictureUrl', p.profile_picture_url,
          'oauthAvatarUrl', p.oauth_avatar_url,
          'sharedAt', ss.created_at,
          'showEarnings', COALESCE(ss.show_earnings, false),
          'hidden', COALESCE(ss.hidden, false),
          'hasSharedCalendarContent',
            latest_shift.latest_shared_shift_date IS NOT NULL
            OR COALESCE(recurring_shifts.has_recurring_shared_shifts, false),
          'latestSharedShiftDate', latest_shift.latest_shared_shift_date,
          'hasRecurringSharedShifts', COALESCE(recurring_shifts.has_recurring_shared_shifts, false)
        ) AS sharer_json,
        ss.created_at
      FROM incoming_shares ss
      JOIN user_profiles p ON p.id = ss.owner_id
      LEFT JOIN LATERAL (
        SELECT MAX(s.shift_date) AS latest_shared_shift_date
        FROM public.user_shifts s
        WHERE s.user_id = ss.owner_id
          AND s.deleted_at IS NULL
      ) latest_shift ON TRUE
      LEFT JOIN LATERAL (
        SELECT EXISTS (
          SELECT 1
          FROM public.recurring_shifts r
          WHERE r.user_id = ss.owner_id
            AND r.deleted_at IS NULL
        ) AS has_recurring_shared_shifts
      ) recurring_shifts ON TRUE
      WHERE ss.blocked_by_user_id IS NULL
    ),
    preview_authorized AS (
      SELECT
        ss.owner_id AS sharer_id,
        COALESCE(ss.show_earnings, false) AS show_earnings
      FROM incoming_shares ss
      WHERE ss.blocked_by_user_id IS NULL
    ),
    preview_rows AS (
      SELECT
        jsonb_build_object(
          'sharer_id', a.sharer_id,
          'show_earnings', a.show_earnings,
          'settings', COALESCE(
            (
              SELECT jsonb_build_object(
                'user_id', us.user_id,
                'created_at', us.created_at,
                'updated_at', us.updated_at,
                'last_active', us.last_active,
                'monthly_goal', us.monthly_goal,
                'monthly_goals_by_month', us.monthly_goals_by_month,
                'default_shifts_view', us.default_shifts_view,
                'profile_picture_url', us.profile_picture_url,
                'payroll_day', us.payroll_day,
                'theme', us.theme,
                'calendar_animation_style', us.calendar_animation_style,
                'half_tax_month', us.half_tax_month,
                'currency', us.currency
              )
              FROM public.user_settings us
              WHERE us.user_id = a.sharer_id
              LIMIT 1
            ),
            jsonb_build_object('user_id', a.sharer_id)
          ),
          'shifts', COALESCE(
            (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'id', s.id,
                  'user_id', s.user_id,
                  'job_id', s.job_id,
                  'shift_date', s.shift_date,
                  'start_time', s.start_time,
                  'end_time', s.end_time,
                  'custom_pause_windows', s.custom_pause_windows,
                  'custom_supplements', CASE WHEN a.show_earnings THEN s.custom_supplements ELSE NULL END,
                  'recurring_id', NULL,
                  'recurring_anchor_weekday', NULL
                )
                ORDER BY s.shift_date ASC, s.start_time ASC, s.id ASC
              )
              FROM public.user_shifts s
              WHERE s.user_id = a.sharer_id
                AND s.deleted_at IS NULL
                AND (p_preview_start_date IS NULL OR s.shift_date >= (p_preview_start_date - ((EXTRACT(isodow FROM p_preview_start_date)::integer - 1) * interval '1 day'))::date)
                AND (p_preview_end_date IS NULL OR s.shift_date <= (p_preview_end_date + ((7 - EXTRACT(isodow FROM p_preview_end_date)::integer) * interval '1 day'))::date)
            ),
            '[]'::jsonb
          ),
          'recurring_shifts', COALESCE(
            (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'id', r.id,
                  'user_id', r.user_id,
                  'job_id', r.job_id,
                  'start_time', r.start_time,
                  'end_time', r.end_time,
                  'repeat_interval_weeks', r.repeat_interval_weeks,
                  'selected_days', r.selected_days,
                  'end_condition', r.end_condition,
                  'exclusions', r.exclusions,
                  'date_specific_pause_windows', r.date_specific_pause_windows,
                  'date_specific_supplements',
                    CASE WHEN a.show_earnings THEN r.date_specific_supplements ELSE NULL END
                )
                ORDER BY r.id ASC
              )
              FROM public.recurring_shifts r
              WHERE r.user_id = a.sharer_id
                AND r.deleted_at IS NULL
            ),
            '[]'::jsonb
          ),
          'snapshots', COALESCE(
            (
              SELECT jsonb_agg(
                CASE
                  WHEN a.show_earnings THEN jsonb_build_object(
                    'id', w.id,
                    'user_id', w.user_id,
                    'job_id', w.job_id,
                    'from_date', w.from_date,
                    'hourly_wage', w.hourly_wage,
                    'wage_level', w.wage_level,
                    'tariff_type_id', w.tariff_type_id,
                    'supplements', w.supplements, 'overtime', COALESCE(w.overtime, jsonb_build_object('enabled', false, 'weeklyThresholdHours', 40, 'rules', jsonb_build_array())),
                    'tax_enabled', w.tax_enabled,
                    'tax_percentage', w.tax_percentage,
                    'break_enabled', w.break_enabled,
                    'break_method', w.break_method,
                    'break_threshold_hours', w.break_threshold_hours,
                    'break_deduction_minutes', w.break_deduction_minutes,
                    'created_at', w.created_at
                  )
                  ELSE jsonb_build_object(
                    'id', w.id,
                    'user_id', w.user_id,
                    'job_id', w.job_id,
                    'from_date', w.from_date,
                    'hourly_wage', 0,
                    'wage_level', NULL,
                    'tariff_type_id', NULL,
                    'supplements', jsonb_build_object('rules', jsonb_build_array()), 'overtime', jsonb_build_object('enabled', false, 'weeklyThresholdHours', 40, 'rules', jsonb_build_array()),
                    'tax_enabled', false,
                    'tax_percentage', 0,
                    'break_enabled', w.break_enabled,
                    'break_method', w.break_method,
                    'break_threshold_hours', w.break_threshold_hours,
                    'break_deduction_minutes', w.break_deduction_minutes,
                    'created_at', w.created_at
                  )
                END
                ORDER BY w.from_date DESC NULLS LAST, w.id ASC
              )
              FROM public.wage_snapshots w
              WHERE w.user_id = a.sharer_id
                AND w.deleted_at IS NULL
            ),
            '[]'::jsonb
          ),
          'jobs', COALESCE(
            (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'id', j.id,
                  'user_id', j.user_id,
                  'name', j.name,
                  'color', j.color,
                  'is_default', j.is_default,
                  'sort_order', j.sort_order,
                  'currency', j.currency,
                  'payroll_day', j.payroll_day,
                  'half_tax_month', j.half_tax_month,
                  'monthly_goal', j.monthly_goal,
                  'archived_at', j.archived_at,
                  'deleted_at', j.deleted_at,
                  'created_at', j.created_at,
                  'updated_at', j.updated_at
                )
                ORDER BY j.sort_order ASC, j.created_at ASC, j.id ASC
              )
              FROM public.jobs j
              WHERE j.user_id = a.sharer_id
            ),
            '[]'::jsonb
          )
        ) AS preview_json,
        a.sharer_id
      FROM preview_authorized a
    )
    SELECT jsonb_build_object(
      'sharers', COALESCE(
        (SELECT jsonb_agg(sharer_json ORDER BY created_at DESC) FROM sharer_rows),
        '[]'::jsonb
      ),
      'friends', COALESCE(
        (SELECT jsonb_agg(friend_json ORDER BY sort_name) FROM visible_friends),
        '[]'::jsonb
      ),
      'blockedFriends', COALESCE(
        (SELECT jsonb_agg(friend_json ORDER BY sort_name) FROM blocked_friends),
        '[]'::jsonb
      ),
      'capacity', jsonb_build_object(
        'canAdd', true,
        'currentCount', COALESCE((SELECT count FROM outgoing_count), 0),
        'limit', 0
      ),
      'previewPayloads', COALESCE(
        (SELECT jsonb_agg(preview_json ORDER BY sharer_id) FROM preview_rows),
        '[]'::jsonb
      )
    )
  );
END;
$function$

;
