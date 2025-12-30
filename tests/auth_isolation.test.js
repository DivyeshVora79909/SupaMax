import { t } from 'tap';
import { supabase, supabaseAdmin, createTestUser, loginUser, deleteTestUser } from './config.js';
import { getClient } from './utils.js';
import { v4 as uuidv4 } from 'uuid';

t.test('Multi-tenancy Isolation and RBAC', async (t) => {
    const orgAName = `Org A ${uuidv4()}`;
    const orgBName = `Org B ${uuidv4()}`;

    let userA, userB, sessionA, sessionB;
    let companyAId, companyBId;

    t.test('Setup: Create two organizations via signup', async (t) => {
        const emailA = `ownerA_${uuidv4()}@test.com`;
        const emailB = `ownerB_${uuidv4()}@test.com`;
        const password = 'Password123!';

        // Sign up User A
        const { data: dataA, error: errorA } = await supabase.auth.signUp({
            email: emailA,
            password,
            options: {
                data: {
                    full_name: 'Owner A',
                    company_name: orgAName
                }
            }
        });
        t.error(errorA, 'User A should sign up');
        userA = dataA.user;

        // Sign up User B
        const { data: dataB, error: errorB } = await supabase.auth.signUp({
            email: emailB,
            password,
            options: {
                data: {
                    full_name: 'Owner B',
                    company_name: orgBName
                }
            }
        });
        t.error(errorB, 'User B should sign up');
        userB = dataB.user;

        // Login to get sessions
        sessionA = await loginUser(emailA, password);
        sessionB = await loginUser(emailB, password);

        t.ok(sessionA.access_token, 'Session A should have access token');
        t.ok(sessionB.access_token, 'Session B should have access token');
    });

    t.test('Tenant Isolation: Owner A cannot see Owner B data', async (t) => {
        const clientA = getClient(sessionA.access_token);
        const clientB = getClient(sessionB.access_token);

        // Create a company in Org A
        const { data: companyA, error: errA } = await clientA
            .from('crm_companies')
            .insert({ name: 'Company A' })
            .select()
            .single();
        if (errA) console.error('Owner A create company error:', errA);
        t.error(errA, 'Owner A should create company');
        companyAId = companyA?.id;

        // Create a company in Org B
        const { data: companyB, error: errB } = await clientB
            .from('crm_companies')
            .insert({ name: 'Company B' })
            .select()
            .single();
        t.error(errB, 'Owner B should create company');
        companyBId = companyB.id;

        // Owner A tries to see Company B
        const { data: seeB, error: errSeeB } = await clientA
            .from('crm_companies')
            .select()
            .eq('id', companyBId);
        t.equal(seeB.length, 0, 'Owner A should NOT see Company B');

        // Owner B tries to see Company A
        const { data: seeA, error: errSeeA } = await clientB
            .from('crm_companies')
            .select()
            .eq('id', companyAId);
        t.equal(seeA.length, 0, 'Owner B should NOT see Company A');
    });

    t.test('RBAC: Member vs Owner', async (t) => {
        const clientA = getClient(sessionA.access_token);

        // Get Org A ID and Member Role ID
        const { data: profileA } = await clientA.from('profiles').select('org_id').single();
        const orgIdA = profileA.org_id;

        const { data: memberRole } = await supabaseAdmin
            .from('roles')
            .select('id')
            .eq('org_id', orgIdA)
            .eq('name', 'Member')
            .single();

        // Create a Member in Org A
        const emailMember = `memberA_${uuidv4()}@test.com`;
        const password = 'Password123!';

        const { data: { user: memberUser }, error: errMember } = await supabaseAdmin.auth.admin.createUser({
            email: emailMember,
            password: password,
            email_confirm: true,
            user_metadata: { full_name: 'Member A' },
            app_metadata: { org_id: orgIdA, role_id: memberRole.id }
        });
        t.error(errMember, 'Member should be created');

        const sessionMember = await loginUser(emailMember, password);


        const clientMember = getClient(sessionMember.access_token);

        // Member tries to create a company (Member has only .read perms)
        const { error: errCreate } = await clientMember
            .from('crm_companies')
            .insert({ name: 'Member Company' });

        t.ok(errCreate, 'Member should NOT be able to create company');

        // Member tries to read company (should work)
        const { data: readCompanies, error: errRead } = await clientMember
            .from('crm_companies')
            .select();
        t.error(errRead, 'Member should be able to read companies');
        t.ok(readCompanies.length > 0, 'Member should see at least one company');

        // Cleanup member
        await deleteTestUser(memberUser.id);
    });

    t.teardown(async () => {
        if (userA) await deleteTestUser(userA.id);
        if (userB) await deleteTestUser(userB.id);
    });
});
