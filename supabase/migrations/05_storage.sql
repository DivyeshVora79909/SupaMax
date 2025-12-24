-- Secure Student Docs
DROP POLICY IF EXISTS "Secure Student Docs" ON storage.objects;
CREATE POLICY "Secure Student Docs" ON storage.objects
FOR ALL TO authenticated
USING (
  bucket_id = 'student-docs'
  AND (storage.foldername(name))[1]::uuid = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
);

-- Secure Teacher Resources
DROP POLICY IF EXISTS "Secure Teacher Resources" ON storage.objects;
CREATE POLICY "Secure Teacher Resources" ON storage.objects
FOR ALL TO authenticated
USING (
  bucket_id = 'teacher-resources'
  AND (storage.foldername(name))[1]::uuid = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
);