DROP POLICY IF EXISTS "Users can read their own profile pictures" ON storage.objects;

CREATE POLICY "Users can read their own profile pictures"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'profile-pictures'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
);
