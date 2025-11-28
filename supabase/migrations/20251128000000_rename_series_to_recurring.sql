-- Rename series_shifts table to recurring_shifts
-- This migration renames the table and updates all associated constraints, indexes, and policies

-- Step 1: Rename the table
ALTER TABLE "public"."series_shifts" RENAME TO "recurring_shifts";

-- Step 2: Rename the primary key constraint
ALTER INDEX "public"."series_shifts_pkey" RENAME TO "recurring_shifts_pkey";

-- Step 3: Rename the foreign key constraint
ALTER TABLE "public"."recurring_shifts" RENAME CONSTRAINT "series_shifts_user_id_fkey" TO "recurring_shifts_user_id_fkey";

-- Step 4: Drop old policies and create new ones with updated names
DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON "public"."recurring_shifts";
DROP POLICY IF EXISTS "Enable insert for users based on user_id" ON "public"."recurring_shifts";
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON "public"."recurring_shifts";
DROP POLICY IF EXISTS "Enable users to view their own data only" ON "public"."recurring_shifts";

CREATE POLICY "Enable delete for users based on user_id"
ON "public"."recurring_shifts"
AS permissive
FOR DELETE
TO authenticated
USING ((( SELECT auth.uid() AS uid) = user_id));

CREATE POLICY "Enable insert for users based on user_id"
ON "public"."recurring_shifts"
AS permissive
FOR INSERT
TO public
WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));

CREATE POLICY "Enable update for users based on user_id"
ON "public"."recurring_shifts"
AS permissive
FOR UPDATE
TO authenticated
USING ((( SELECT auth.uid() AS uid) = user_id))
WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));

CREATE POLICY "Enable users to view their own data only"
ON "public"."recurring_shifts"
AS permissive
FOR SELECT
TO authenticated
USING ((( SELECT auth.uid() AS uid) = user_id));
