-- Function: enforce_shift_shares_update_columns
-- Description: Trigger function that enforces column-level update restrictions on shift_shares
-- Used by: BEFORE UPDATE trigger on shift_shares

CREATE OR REPLACE FUNCTION public.enforce_shift_shares_update_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
declare
  v_uid uuid := (select auth.uid());
begin
  if current_setting('tidex.allow_shift_share_abuse_block_update', true) = 'true' then
    return new;
  end if;

  -- Allow trusted maintenance/service-role updates without an auth user.
  if v_uid is null then
    return new;
  end if;

  -- Immutable columns
  if new.id != old.id then
    raise exception 'Cannot modify id column';
  end if;
  if new.owner_id != old.owner_id then
    raise exception 'Cannot modify owner_id column';
  end if;
  if new.viewer_id != old.viewer_id then
    raise exception 'Cannot modify viewer_id column';
  end if;
  if new.created_at != old.created_at then
    raise exception 'Cannot modify created_at column';
  end if;

  -- Viewer updates
  if v_uid = old.viewer_id then
    if new.show_earnings is distinct from old.show_earnings then
      raise exception 'Viewers cannot modify show_earnings column';
    end if;
    if new.owner_muted is distinct from old.owner_muted then
      raise exception 'Viewers cannot modify owner_muted column';
    end if;
    if new.blocked_by_user_id is distinct from old.blocked_by_user_id then
      raise exception 'Clients cannot modify blocked_by_user_id directly';
    end if;
  end if;

  -- Owner updates
  if v_uid = old.owner_id then
    if new.blocked is distinct from old.blocked then
      raise exception 'Owners cannot modify blocked column';
    end if;
    if new.hidden is distinct from old.hidden then
      raise exception 'Owners cannot modify hidden column';
    end if;
    if new.muted is distinct from old.muted then
      raise exception 'Owners cannot modify muted column';
    end if;
    if new.blocked_by_user_id is distinct from old.blocked_by_user_id then
      raise exception 'Clients cannot modify blocked_by_user_id directly';
    end if;
  end if;

  -- Direct client writes must not set abuse-block state yet.
  if v_uid is not null and new.blocked_by_user_id is distinct from old.blocked_by_user_id then
    raise exception 'Clients cannot modify blocked_by_user_id directly';
  end if;

  return new;
end;
$function$;
