-- These SECURITY DEFINER functions are implementation helpers, not direct
-- mobile RPC contract. They are called from other definer functions or policy
-- helpers that remain executable where Postgres requires it.
REVOKE EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.can_post_to_thread(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.is_user_pair_abuse_blocked(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.user_has_verified_mfa_factors() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.user_has_any_shifts(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.user_has_shift_in_month(uuid, date) FROM authenticated;
