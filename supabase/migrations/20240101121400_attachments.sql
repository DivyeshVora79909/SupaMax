INSERT INTO
    storage.buckets (id, name, public)
VALUES (
        'resources',
        'resources',
        FALSE
    ) ON CONFLICT (id) DO NOTHING;

-- CREATE INDEX idx_storage_rls_lookup
-- ON storage.objects (
--     bucket_id,
--     ((metadata ->> 'owner_id')::uuid)
-- );

CREATE POLICY "rls_resources_select"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'resources'
        AND _i_dominate((metadata->>'owner_id')::uuid)
    );

CREATE POLICY "rls_resources_select_via_parent"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'resources'
        AND _is_nonuser_parent((metadata->>'owner_id')::uuid)
    );

CREATE POLICY "rls_resources_insert"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'resources'
        AND _i_dominate((metadata->>'owner_id')::uuid)
    );

CREATE POLICY "rls_resources_update"
    ON storage.objects FOR UPDATE TO authenticated
    USING (
        bucket_id = 'resources'
        AND _i_dominate((metadata->>'owner_id')::uuid)
    );

CREATE POLICY "rls_resources_delete"
    ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'resources'
        AND _i_dominate((metadata->>'owner_id')::uuid)
    );