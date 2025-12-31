-- Function: increment_wagey_invocation
-- Description: Atomically increments Wagey (AI) invocation count with monthly reset
-- Used by: Wagey chat feature rate limiting

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
  v_new_count integer;
  v_allowed boolean;
begin
  -- Get current invocations with row lock
  select p.wagey_invocations
  into v_current
  from public.profiles p
  where p.id = p_user_id
  for update;

  if v_current is null then
    v_current := '{"count": 0, "month": null}'::jsonb;
  end if;

  v_count := coalesce((v_current->>'count')::integer, 0);
  v_month := v_current->>'month';

  if v_month is null or v_month != p_current_month then
    v_new_count := 1;
    v_allowed := true;
  else
    if v_count < p_max_invocations then
      v_new_count := v_count + 1;
      v_allowed := true;
    else
      v_new_count := v_count;
      v_allowed := false;
    end if;
  end if;

  if v_allowed then
    update public.profiles
    set
      wagey_invocations = jsonb_build_object('count', v_new_count, 'month', p_current_month),
      updated_at = now()
    where id = p_user_id;
  end if;

  return jsonb_build_object(
    'allowed', v_allowed,
    'count', v_new_count,
    'remaining', greatest(0, p_max_invocations - v_new_count)
  );
end;
$function$;
