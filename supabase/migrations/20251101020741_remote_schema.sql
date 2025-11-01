create extension if not exists "moddatetime" with schema "extensions";

drop policy "read own subs" on "public"."subscriptions";

drop policy "Users can insert own shifts" on "public"."user_shifts";

drop policy "Users can update own shifts" on "public"."user_shifts";

revoke delete on table "public"."profiles" from "anon";

revoke insert on table "public"."profiles" from "anon";

revoke references on table "public"."profiles" from "anon";

revoke select on table "public"."profiles" from "anon";

revoke trigger on table "public"."profiles" from "anon";

revoke truncate on table "public"."profiles" from "anon";

revoke update on table "public"."profiles" from "anon";

revoke delete on table "public"."profiles" from "authenticated";

revoke insert on table "public"."profiles" from "authenticated";

revoke references on table "public"."profiles" from "authenticated";

revoke select on table "public"."profiles" from "authenticated";

revoke trigger on table "public"."profiles" from "authenticated";

revoke truncate on table "public"."profiles" from "authenticated";

revoke update on table "public"."profiles" from "authenticated";

revoke delete on table "public"."profiles" from "service_role";

revoke insert on table "public"."profiles" from "service_role";

revoke references on table "public"."profiles" from "service_role";

revoke select on table "public"."profiles" from "service_role";

revoke trigger on table "public"."profiles" from "service_role";

revoke truncate on table "public"."profiles" from "service_role";

revoke update on table "public"."profiles" from "service_role";

revoke delete on table "public"."subscriptions" from "anon";

revoke insert on table "public"."subscriptions" from "anon";

revoke references on table "public"."subscriptions" from "anon";

revoke select on table "public"."subscriptions" from "anon";

revoke trigger on table "public"."subscriptions" from "anon";

revoke truncate on table "public"."subscriptions" from "anon";

revoke update on table "public"."subscriptions" from "anon";

revoke delete on table "public"."subscriptions" from "authenticated";

revoke insert on table "public"."subscriptions" from "authenticated";

revoke references on table "public"."subscriptions" from "authenticated";

revoke select on table "public"."subscriptions" from "authenticated";

revoke trigger on table "public"."subscriptions" from "authenticated";

revoke truncate on table "public"."subscriptions" from "authenticated";

revoke update on table "public"."subscriptions" from "authenticated";

revoke delete on table "public"."subscriptions" from "service_role";

revoke insert on table "public"."subscriptions" from "service_role";

revoke references on table "public"."subscriptions" from "service_role";

revoke select on table "public"."subscriptions" from "service_role";

revoke trigger on table "public"."subscriptions" from "service_role";

revoke truncate on table "public"."subscriptions" from "service_role";

revoke update on table "public"."subscriptions" from "service_role";

revoke delete on table "public"."user_settings" from "anon";

revoke insert on table "public"."user_settings" from "anon";

revoke references on table "public"."user_settings" from "anon";

revoke select on table "public"."user_settings" from "anon";

revoke trigger on table "public"."user_settings" from "anon";

revoke truncate on table "public"."user_settings" from "anon";

revoke update on table "public"."user_settings" from "anon";

revoke delete on table "public"."user_settings" from "authenticated";

revoke insert on table "public"."user_settings" from "authenticated";

revoke references on table "public"."user_settings" from "authenticated";

revoke select on table "public"."user_settings" from "authenticated";

revoke trigger on table "public"."user_settings" from "authenticated";

revoke truncate on table "public"."user_settings" from "authenticated";

revoke update on table "public"."user_settings" from "authenticated";

revoke delete on table "public"."user_settings" from "service_role";

revoke insert on table "public"."user_settings" from "service_role";

revoke references on table "public"."user_settings" from "service_role";

revoke select on table "public"."user_settings" from "service_role";

revoke trigger on table "public"."user_settings" from "service_role";

revoke truncate on table "public"."user_settings" from "service_role";

revoke update on table "public"."user_settings" from "service_role";

revoke delete on table "public"."user_shifts" from "anon";

revoke insert on table "public"."user_shifts" from "anon";

revoke references on table "public"."user_shifts" from "anon";

revoke select on table "public"."user_shifts" from "anon";

revoke trigger on table "public"."user_shifts" from "anon";

revoke truncate on table "public"."user_shifts" from "anon";

revoke update on table "public"."user_shifts" from "anon";

revoke delete on table "public"."user_shifts" from "authenticated";

revoke insert on table "public"."user_shifts" from "authenticated";

revoke references on table "public"."user_shifts" from "authenticated";

revoke select on table "public"."user_shifts" from "authenticated";

revoke trigger on table "public"."user_shifts" from "authenticated";

revoke truncate on table "public"."user_shifts" from "authenticated";

revoke update on table "public"."user_shifts" from "authenticated";

revoke delete on table "public"."user_shifts" from "service_role";

revoke insert on table "public"."user_shifts" from "service_role";

revoke references on table "public"."user_shifts" from "service_role";

revoke select on table "public"."user_shifts" from "service_role";

revoke trigger on table "public"."user_shifts" from "service_role";

revoke truncate on table "public"."user_shifts" from "service_role";

revoke update on table "public"."user_shifts" from "service_role";


  create table "public"."series_shifts" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null default auth.uid(),
    "start_time" time with time zone not null,
    "end_time" time with time zone not null,
    "repeat_interval_weeks" smallint not null,
    "selected_days" jsonb not null,
    "end_condition" jsonb,
    "exclusions" jsonb
      );


alter table "public"."series_shifts" enable row level security;


  create table "public"."stripe_events" (
    "id" text not null,
    "type" text not null,
    "received_at" timestamp with time zone not null default now(),
    "processed_at" timestamp with time zone,
    "attempts" integer not null default 0,
    "last_error" text
      );


alter table "public"."stripe_events" enable row level security;

alter table "public"."subscriptions" add column "cancel_at" timestamp with time zone;

alter table "public"."subscriptions" add column "cancel_at_period_end" boolean default false;

alter table "public"."subscriptions" add column "canceled_at" timestamp with time zone;

alter table "public"."subscriptions" add column "cancellation_comment" text;

alter table "public"."subscriptions" add column "cancellation_feedback" text;

alter table "public"."subscriptions" add column "cancellation_reason" text;

alter table "public"."subscriptions" alter column "stripe_customer_id" set not null;

alter table "public"."user_settings" drop column "audit_break_calculations";

alter table "public"."user_settings" drop column "break_policy";

alter table "public"."user_settings" drop column "direct_time_input";

alter table "public"."user_settings" drop column "pause_deduction";

alter table "public"."user_settings" alter column "default_shifts_view" set default 'calendar'::character varying;

alter table "public"."user_shifts" drop column "pause_duration_hours";

alter table "public"."user_shifts" drop column "series_id";

alter table "public"."user_shifts" add column "hourly_wage_snapshot" numeric(6,2);

alter table "public"."user_shifts" add column "supplement_rules_snapshot" jsonb;

CREATE INDEX idx_subscriptions_stripe_customer ON public.subscriptions USING btree (stripe_customer_id);

CREATE INDEX idx_subscriptions_stripe_subscription ON public.subscriptions USING btree (stripe_subscription_id);

CREATE UNIQUE INDEX series_shifts_pkey ON public.series_shifts USING btree (id);

CREATE UNIQUE INDEX stripe_events_pkey ON public.stripe_events USING btree (id);

CREATE INDEX subscriptions_customer_id_idx ON public.subscriptions USING btree (stripe_customer_id);

CREATE UNIQUE INDEX subscriptions_customer_unique ON public.subscriptions USING btree (stripe_customer_id);

CREATE INDEX subscriptions_user_id_idx ON public.subscriptions USING btree (user_id);

CREATE UNIQUE INDEX subscriptions_user_unique ON public.subscriptions USING btree (user_id);

alter table "public"."series_shifts" add constraint "series_shifts_pkey" PRIMARY KEY using index "series_shifts_pkey";

alter table "public"."stripe_events" add constraint "stripe_events_pkey" PRIMARY KEY using index "stripe_events_pkey";

alter table "public"."series_shifts" add constraint "series_shifts_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;

alter table "public"."series_shifts" validate constraint "series_shifts_user_id_fkey";

alter table "public"."subscriptions" add constraint "stripe_customer_format" CHECK ((stripe_customer_id ~ '^cus_[A-Za-z0-9]+$'::text)) not valid;

alter table "public"."subscriptions" validate constraint "stripe_customer_format";

alter table "public"."subscriptions" add constraint "subscriptions_customer_unique" UNIQUE using index "subscriptions_customer_unique";

alter table "public"."subscriptions" add constraint "subscriptions_user_fk" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."subscriptions" validate constraint "subscriptions_user_fk";

alter table "public"."subscriptions" add constraint "subscriptions_user_unique" UNIQUE using index "subscriptions_user_unique";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.user_has_any_shifts(u uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.user_shifts where user_id = u);
$function$
;

CREATE OR REPLACE FUNCTION public.user_has_shift_in_month(u uuid, d date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.user_shifts
    where user_id = u
      and date_trunc('month', shift_date)::date = date_trunc('month', d)::date
  );
$function$
;

CREATE OR REPLACE FUNCTION public.get_tariff_rate(level smallint)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF level = 0 OR level IS NULL THEN
    RETURN NULL; -- 0 => use custom wage
  END IF;
  RETURN CASE level
    WHEN -1 THEN 129.91
    WHEN -2 THEN 132.90
    WHEN 1 THEN 188.58
    WHEN 2 THEN 200.32
    WHEN 3 THEN 208.70
    WHEN 4 THEN 222.58
    WHEN 5 THEN 238.10
    WHEN 6 THEN 256.14
    ELSE NULL
  END;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end; $function$
;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  new.updated_at := now();
  return new;
end; $function$
;


  create policy "update own profile"
  on "public"."profiles"
  as permissive
  for update
  to authenticated
using ((id = auth.uid()))
with check ((id = auth.uid()));



  create policy "Enable delete for users based on user_id"
  on "public"."series_shifts"
  as permissive
  for delete
  to authenticated
using ((( SELECT auth.uid() AS uid) = user_id));



  create policy "Enable insert for users based on user_id"
  on "public"."series_shifts"
  as permissive
  for insert
  to public
with check ((( SELECT auth.uid() AS uid) = user_id));



  create policy "Enable update for users based on user_id"
  on "public"."series_shifts"
  as permissive
  for update
  to authenticated
using ((( SELECT auth.uid() AS uid) = user_id))
with check ((( SELECT auth.uid() AS uid) = user_id));



  create policy "Enable users to view their own data only"
  on "public"."series_shifts"
  as permissive
  for select
  to authenticated
using ((( SELECT auth.uid() AS uid) = user_id));



  create policy "Enable users to view their own data only"
  on "public"."subscriptions"
  as permissive
  for select
  to authenticated
using ((( SELECT auth.uid() AS uid) = user_id));



  create policy "service_role_full_access"
  on "public"."subscriptions"
  as permissive
  for all
  to service_role
using (true)
with check (true);



  create policy "update own settings"
  on "public"."user_settings"
  as permissive
  for update
  to authenticated
using ((user_id = auth.uid()))
with check ((user_id = auth.uid()));



  create policy "insert_user_shifts_paid_or_existing_month"
  on "public"."user_shifts"
  as permissive
  for insert
  to public
with check (((user_id = auth.uid()) AND ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (COALESCE(profiles.before_paywall, false) = true)))) OR (EXISTS ( SELECT 1
   FROM subscriptions
  WHERE ((subscriptions.user_id = auth.uid()) AND (subscriptions.status = 'active'::text)))) OR ((NOT user_has_any_shifts(auth.uid())) OR user_has_shift_in_month(auth.uid(), shift_date)))));



  create policy "update_user_shifts_paid_or_existing_month"
  on "public"."user_shifts"
  as permissive
  for update
  to public
using ((user_id = auth.uid()))
with check (((user_id = auth.uid()) AND ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (COALESCE(profiles.before_paywall, false) = true)))) OR (EXISTS ( SELECT 1
   FROM subscriptions
  WHERE ((subscriptions.user_id = auth.uid()) AND (subscriptions.status = 'active'::text)))) OR ((NOT user_has_any_shifts(auth.uid())) OR user_has_shift_in_month(auth.uid(), shift_date)))));


CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.subscriptions FOR EACH ROW EXECUTE FUNCTION extensions.moddatetime('updated_at');


