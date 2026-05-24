-- Retire the pre-consolidation Friends tab bootstrap RPCs.
-- Supported clients now use public.get_friends_tab_bootstrap(date, date).

DROP FUNCTION IF EXISTS public.get_my_sharer_preview_payloads(uuid[], date, date);
DROP FUNCTION IF EXISTS public.get_my_sharers();
DROP FUNCTION IF EXISTS public.get_sharing_friends_api();
