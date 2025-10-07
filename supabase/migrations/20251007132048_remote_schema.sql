
\restrict h46IkziUcEPIkbQcDg8mmkEa0y2fyeXPT1SxJc3QqXicyooAFlmeeaZFhqAnPNh


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."get_tariff_rate"("level" smallint) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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
$$;


ALTER FUNCTION "public"."get_tariff_rate"("level" smallint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end; $$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  new.updated_at := now();
  return new;
end; $$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "before_paywall" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "stripe_customer_id" "text",
    "stripe_subscription_id" "text",
    "status" "text" DEFAULT 'incomplete'::"text" NOT NULL,
    "current_period_end" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "price_id" "text"
);


ALTER TABLE "public"."subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_settings" (
    "user_id" "uuid" NOT NULL,
    "use_preset" boolean DEFAULT true,
    "custom_wage" numeric DEFAULT 200,
    "current_wage_level" integer DEFAULT 1,
    "custom_bonuses" "jsonb",
    "pause_deduction" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_active" timestamp with time zone DEFAULT "now"(),
    "direct_time_input" boolean DEFAULT false,
    "monthly_goal" integer DEFAULT 20000,
    "default_shifts_view" character varying(10) DEFAULT 'list'::character varying,
    "profile_picture_url" "text",
    "tax_deduction_enabled" boolean DEFAULT false,
    "tax_percentage" numeric(5,2) DEFAULT 0.0,
    "payroll_day" integer DEFAULT 15,
    "pause_deduction_enabled" boolean DEFAULT true,
    "pause_deduction_method" "text" DEFAULT 'proportional'::"text",
    "pause_threshold_hours" numeric(3,1) DEFAULT 5.5,
    "pause_deduction_minutes" integer DEFAULT 30,
    "audit_break_calculations" boolean DEFAULT true,
    "break_policy" "text" DEFAULT 'fixed_0_5_over_5_5h'::"text",
    "theme" "text" DEFAULT 'dark'::"text" NOT NULL,
    CONSTRAINT "tax_percentage_range_check" CHECK ((("tax_percentage" >= 0.0) AND ("tax_percentage" <= 100.0))),
    CONSTRAINT "user_settings_default_shifts_view_check" CHECK ((("default_shifts_view")::"text" = ANY (ARRAY[('list'::character varying)::"text", ('calendar'::character varying)::"text"]))),
    CONSTRAINT "user_settings_pause_deduction_method_check" CHECK (("pause_deduction_method" = ANY (ARRAY['proportional'::"text", 'base_only'::"text", 'end_of_shift'::"text", 'none'::"text"]))),
    CONSTRAINT "user_settings_pause_deduction_minutes_check" CHECK (("pause_deduction_minutes" > 0)),
    CONSTRAINT "user_settings_pause_threshold_hours_check" CHECK (("pause_threshold_hours" > (0)::numeric)),
    CONSTRAINT "user_settings_payroll_day_check" CHECK ((("payroll_day" >= 1) AND ("payroll_day" <= 31))),
    CONSTRAINT "user_settings_theme_check" CHECK (("theme" = ANY (ARRAY['light'::"text", 'dark'::"text", 'system'::"text"])))
);


ALTER TABLE "public"."user_settings" OWNER TO "postgres";


COMMENT ON COLUMN "public"."user_settings"."default_shifts_view" IS 'User preference for default shifts view: list or calendar';



COMMENT ON COLUMN "public"."user_settings"."tax_deduction_enabled" IS 'Whether tax deduction is enabled for salary calculations';



COMMENT ON COLUMN "public"."user_settings"."tax_percentage" IS 'Tax percentage to deduct from salary (0.0 to 100.0)';



COMMENT ON COLUMN "public"."user_settings"."payroll_day" IS 'Day of the month when user receives payroll (1-31), defaults to 15';



CREATE TABLE IF NOT EXISTS "public"."user_shifts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "shift_date" "date" NOT NULL,
    "start_time" "text" NOT NULL,
    "end_time" "text" NOT NULL,
    "shift_type" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "series_id" "uuid",
    "pause_duration_hours" numeric(4,2) DEFAULT 0.5
);


ALTER TABLE "public"."user_shifts" OWNER TO "postgres";


COMMENT ON COLUMN "public"."user_shifts"."pause_duration_hours" IS 'Varighet av pause i timer (standard 0.5 = 30 min)';



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_user_id_unique" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."user_settings"
    ADD CONSTRAINT "user_settings_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."user_shifts"
    ADD CONSTRAINT "user_shifts_pkey" PRIMARY KEY ("id");



CREATE INDEX "user_shifts_user_date_idx" ON "public"."user_shifts" USING "btree" ("user_id", "shift_date");



CREATE OR REPLACE TRIGGER "trg_profiles_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_settings"
    ADD CONSTRAINT "user_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_shifts"
    ADD CONSTRAINT "user_shifts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Users can delete own shifts" ON "public"."user_shifts" FOR DELETE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can insert own shifts" ON "public"."user_shifts" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can update own shifts" ON "public"."user_shifts" FOR UPDATE USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view own shifts" ON "public"."user_shifts" FOR SELECT USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "insert own profile" ON "public"."profiles" FOR INSERT TO "authenticated" WITH CHECK (("id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "read own profile" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "read own subs" ON "public"."subscriptions" FOR SELECT TO "authenticated" USING (("id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_settings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_settings_all_merged" ON "public"."user_settings" TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."user_shifts" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";





GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."get_tariff_rate"("level" smallint) TO "anon";
GRANT ALL ON FUNCTION "public"."get_tariff_rate"("level" smallint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_tariff_rate"("level" smallint) TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";


















GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."user_settings" TO "anon";
GRANT ALL ON TABLE "public"."user_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."user_settings" TO "service_role";



GRANT ALL ON TABLE "public"."user_shifts" TO "anon";
GRANT ALL ON TABLE "public"."user_shifts" TO "authenticated";
GRANT ALL ON TABLE "public"."user_shifts" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






























\unrestrict h46IkziUcEPIkbQcDg8mmkEa0y2fyeXPT1SxJc3QqXicyooAFlmeeaZFhqAnPNh

RESET ALL;
