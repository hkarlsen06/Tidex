-- Tidex is free. Every user, including future signups, gets the grandfathered
-- Pro entitlement so installed app versions stop enforcing the paywall.

ALTER TABLE public.profiles ALTER COLUMN before_paywall SET DEFAULT true;

UPDATE public.profiles SET before_paywall = true WHERE NOT before_paywall;
