-- Wagey is gone. wagey-chat-v2 is a stub that makes no database calls, and
-- apple-verify-purchase no longer credits Wagey credit packs.
--
-- user_settings.ai_data_sharing_enabled and user_settings.wagey_showcase_seen
-- stay for now: shipped app versions still write them when they push settings.

DROP FUNCTION IF EXISTS public.get_wagey_access_context(uuid);
DROP FUNCTION IF EXISTS public.increment_wagey_bonus(uuid, integer);
DROP FUNCTION IF EXISTS public.increment_wagey_invocation(uuid, text, integer);
DROP FUNCTION IF EXISTS public.resolve_user_shift_id(text);
DROP FUNCTION IF EXISTS public.resolve_recurring_shift_id(text);
DROP FUNCTION IF EXISTS public.resolve_wage_snapshot_id(text);
DROP FUNCTION IF EXISTS public.resolve_user_event_id(text);
DROP FUNCTION IF EXISTS public.resolve_payroll_adjustment_id(text);

ALTER TABLE public.profiles DROP COLUMN IF EXISTS wagey_invocations;

DROP TABLE IF EXISTS public.consumable_transactions;
