import { t } from 'tap';
import { supabase, loginUser, deleteTestUser } from './config.js';
import { getClient, delay } from './utils.js';
import { v4 as uuidv4 } from 'uuid';

t.test('Performance and Scalability', async (t) => {
    let user, session;

    t.test('Setup: Create organization and seed data', async (t) => {
        const email = `perf_test_${uuidv4()}@test.com`;
        const password = 'Password123!';

        const { data } = await supabase.auth.signUp({
            email,
            password,
            options: { data: { company_name: 'Perf Org' } }
        });
        user = data.user;
        session = await loginUser(email, password);
    });

    t.test('Latency: Batch Insert and Fetch', async (t) => {
        const client = getClient(session.access_token);

        // Batch insert 100 companies
        const startInsert = Date.now();
        const companies = Array.from({ length: 100 }, (_, i) => ({ name: `Company ${i}` }));
        const { data: inserted, error: errInsert } = await client
            .from('crm_companies')
            .insert(companies)
            .select();
        const endInsert = Date.now();

        t.error(errInsert, 'Should batch insert companies');
        t.equal(inserted.length, 100, 'Should insert 100 companies');
        console.log(`Batch Insert 100 companies took: ${endInsert - startInsert}ms`);

        // Fetch all companies with a filter
        const startFetch = Date.now();
        const { data: fetched, error: errFetch } = await client
            .from('crm_companies')
            .select()
            .ilike('name', 'Company 1%');
        const endFetch = Date.now();

        t.error(errFetch, 'Should fetch companies');
        t.ok(fetched.length >= 11, 'Should fetch at least 11 companies (1, 10-19)');
        console.log(`Filtered Fetch took: ${endFetch - startFetch}ms`);

        t.ok(endFetch - startFetch < 200, 'Fetch should be fast (< 200ms)');
    });

    t.test('Concurrency: Multiple simultaneous requests', async (t) => {
        const client = getClient(session.access_token);

        const start = Date.now();
        const requests = Array.from({ length: 20 }, () =>
            client.from('crm_companies').select('count', { count: 'exact', head: true })
        );

        const results = await Promise.all(requests);
        const end = Date.now();

        results.forEach((res, i) => {
            t.error(res.error, `Request ${i} should succeed`);
        });

        console.log(`20 concurrent count requests took: ${end - start}ms`);
        t.ok(end - start < 1000, 'Concurrent requests should be handled efficiently');
    });

    t.teardown(async () => {
        if (user) await deleteTestUser(user.id);
    });
});
