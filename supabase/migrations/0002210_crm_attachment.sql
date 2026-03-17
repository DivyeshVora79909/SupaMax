-- 1. Create the 'resources' bucket
INSERT INTO storage.buckets(id, name, public)
    VALUES ('resources', 'resources', FALSE)
ON CONFLICT (id)
    DO NOTHING;

-- 2. Delegated RLS
CREATE POLICY "rls_resources_delegate" ON storage.objects
    FOR ALL TO authenticated
        USING (bucket_id = 'resources'
            AND ((name LIKE 'account/%' AND EXISTS (
                SELECT
                    1
                FROM
                    account
                WHERE
                    id::text = split_part(name, '/', 2))) OR (name LIKE 'contact/%' AND EXISTS (
                        SELECT
                            1
                        FROM
                            contact
                        WHERE
                            id::text = split_part(name, '/', 2))) OR (name LIKE 'opportunity/%' AND EXISTS (
                                SELECT
                                    1
                                FROM
                                    opportunity
                                WHERE
                                    id::text = split_part(name, '/', 2))) OR (name LIKE 'project/%' AND EXISTS (
                                        SELECT
                                            1
                                        FROM
                                            project
                                        WHERE
                                            id::text = split_part(name, '/', 2)))))
                                        WITH CHECK (bucket_id = 'resources'
                                        AND ((name LIKE 'account/%' AND EXISTS (
                                            SELECT
                                                1
                                            FROM
                                                account
                                            WHERE
                                                id::text = split_part(name, '/', 2))) OR (name LIKE 'contact/%' AND EXISTS (
                                                    SELECT
                                                        1
                                                    FROM
                                                        contact
                                                    WHERE
                                                        id::text = split_part(name, '/', 2))) OR (name LIKE 'opportunity/%' AND EXISTS (
                                                            SELECT
                                                                1
                                                            FROM
                                                                opportunity
                                                            WHERE
                                                                id::text = split_part(name, '/', 2))) OR (name LIKE 'project/%' AND EXISTS (
                                                                    SELECT
                                                                        1
                                                                    FROM
                                                                        project
                                                                    WHERE
                                                                        id::text = split_part(name, '/', 2)))));

