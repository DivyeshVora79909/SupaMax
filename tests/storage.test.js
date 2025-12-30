import { t } from 'tap';
import { supabase, loginUser, deleteTestUser, supabaseAdmin } from './config.js';
import { getClient } from './utils.js';
import { v4 as uuidv4 } from 'uuid';

t.test('Storage Isolation', async (t) => {
    let userA, sessionA, orgIdA;
    let userB, sessionB, orgIdB;

    t.test('Setup: Create two organizations', async (t) => {
        // User A
        const emailA = `storageA_${uuidv4()}@test.com`;
        const password = 'Password123!';
        await supabase.auth.signUp({ email: emailA, password, options: { data: { company_name: 'Storage Org A' } } });
        sessionA = await loginUser(emailA, password);
        userA = sessionA.user;

        const clientA = getClient(sessionA.access_token);
        const { data: profileA } = await clientA.from('profiles').select('org_id').single();
        orgIdA = profileA.org_id;

        // User B
        const emailB = `storageB_${uuidv4()}@test.com`;
        await supabase.auth.signUp({ email: emailB, password, options: { data: { company_name: 'Storage Org B' } } });
        sessionB = await loginUser(emailB, password);
        userB = sessionB.user;

        const clientB = getClient(sessionB.access_token);
        const { data: profileB } = await clientB.from('profiles').select('org_id').single();
        orgIdB = profileB.org_id;

        // Ensure buckets exist (Admin)
        await supabaseAdmin.storage.createBucket('student-docs', { public: false }).catch(() => { });
    });

    t.test('Storage: User A can upload to their own folder', async (t) => {
        const clientA = getClient(sessionA.access_token);
        const fileName = `${orgIdA}/test.txt`;
        const content = 'Hello Org A';

        const { data, error } = await clientA.storage
            .from('student-docs')
            .upload(fileName, content, { contentType: 'text/plain', upsert: true });

        t.error(error, 'User A should upload to their folder');
        t.ok(data, 'Upload should return data');
    });

    t.test('Storage: User A CANNOT upload to User B folder', async (t) => {
        const clientA = getClient(sessionA.access_token);
        const fileName = `${orgIdB}/stolen.txt`;
        const content = 'I am an attacker';

        const { error } = await clientA.storage
            .from('student-docs')
            .upload(fileName, content, { contentType: 'text/plain' });

        t.ok(error, 'User A should NOT be able to upload to Org B folder');
    });

    t.test('Storage: User B CANNOT read User A file', async (t) => {
        const clientB = getClient(sessionB.access_token);
        const fileName = `${orgIdA}/test.txt`;

        const { data, error } = await clientB.storage
            .from('student-docs')
            .download(fileName);

        t.ok(error, 'User B should NOT be able to download Org A file');
    });

    t.teardown(async () => {
        if (userA) await deleteTestUser(userA.id);
        if (userB) await deleteTestUser(userB.id);
    });
});
