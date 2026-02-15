-- Function: increment_wagey_bonus
-- Description: Atomically adds bonus credits to a user's wagey_invocations JSON
-- Used by: apple-verify-purchase edge function when processing consumable purchases

CREATE OR REPLACE FUNCTION public.increment_wagey_bonus(p_user_id uuid, p_credits integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_current jsonb;
  v_bonus integer;
begin
  select p.wagey_invocations
  into v_current
  from public.profiles p
  where p.id = p_user_id
  for update;

  if v_current is null then
    v_current := '{"count": 0, "month": null, "bonus": 0}'::jsonb;
  end if;

  v_bonus := coalesce((v_current->>'bonus')::integer, 0) + p_credits;

  update public.profiles
  set
    wagey_invocations = v_current || jsonb_build_object('bonus', v_bonus),
    updated_at = now()
  where id = p_user_id;
end;
$function$;

-- Function: increment_wagey_invocation
-- Description: Atomically increments Wagey (AI) invocation count with monthly reset
-- Used by: Wagey chat feature rate limiting
-- Supports bonus credits: when monthly limit is reached, consumes bonus instead of blocking

CREATE OR REPLACE FUNCTION public.increment_wagey_invocation(p_user_id uuid, p_current_month text, p_max_invocations integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_current jsonb;
  v_count integer;
  v_month text;
  v_bonus integer;
  v_new_count integer;
  v_new_bonus integer;
  v_allowed boolean;
begin
  -- Get current invocations with row lock
  select p.wagey_invocations
  into v_current
  from public.profiles p
  where p.id = p_user_id
  for update;

  if v_current is null then
    v_current := '{"count": 0, "month": null, "bonus": 0}'::jsonb;
  end if;

  v_count := coalesce((v_current->>'count')::integer, 0);
  v_month := v_current->>'month';
  v_bonus := coalesce((v_current->>'bonus')::integer, 0);

  if v_month is null or v_month != p_current_month then
    -- New month: reset count, preserve bonus
    v_new_count := 1;
    v_new_bonus := v_bonus;
    v_allowed := true;
  else
    if v_count < p_max_invocations then
      -- Within monthly limit
      v_new_count := v_count + 1;
      v_new_bonus := v_bonus;
      v_allowed := true;
    elsif v_bonus > 0 then
      -- Monthly limit reached but bonus available: consume one bonus credit
      v_new_count := v_count;
      v_new_bonus := v_bonus - 1;
      v_allowed := true;
    else
      -- Monthly limit reached, no bonus
      v_new_count := v_count;
      v_new_bonus := v_bonus;
      v_allowed := false;
    end if;
  end if;

  if v_allowed then
    update public.profiles
    set
      wagey_invocations = jsonb_build_object('count', v_new_count, 'month', p_current_month, 'bonus', v_new_bonus),
      updated_at = now()
    where id = p_user_id;
  end if;

  return jsonb_build_object(
    'allowed', v_allowed,
    'count', v_new_count,
    'remaining', greatest(0, p_max_invocations - v_new_count),
    'bonus', v_new_bonus
  );
end;
$function$;
