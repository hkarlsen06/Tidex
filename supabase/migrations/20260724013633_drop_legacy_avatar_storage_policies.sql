-- Retire dashboard-created policies for the removed `avatars` bucket and
-- duplicate shorthand policies for the current `profile-pictures` bucket.
-- The canonical profile-picture policies remain in place.
DROP POLICY IF EXISTS "avatars: insert own" ON storage.objects;
DROP POLICY IF EXISTS "avatars: update own" ON storage.objects;
DROP POLICY IF EXISTS "delete own avatar" ON storage.objects;
DROP POLICY IF EXISTS "read own avatar" ON storage.objects;
DROP POLICY IF EXISTS "update own avatar" ON storage.objects;
DROP POLICY IF EXISTS "upload own avatar" ON storage.objects;

DROP POLICY IF EXISTS "pfp delete own" ON storage.objects;
DROP POLICY IF EXISTS "pfp insert own" ON storage.objects;
DROP POLICY IF EXISTS "pfp update own" ON storage.objects;
