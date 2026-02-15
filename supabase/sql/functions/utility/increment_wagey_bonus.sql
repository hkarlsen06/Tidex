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
