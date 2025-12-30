import { t } from 'tap';
import { supabase, supabaseAdmin, loginUser, deleteTestUser } from './config.js';
import { getClient } from './utils.js';
import { v4 as uuidv4 } from 'uuid';

t.test('Triggers and Automation', async (t) => {
    let user, session, orgId, roleId;

    t.test('Setup: Create organization via signup', async (t) => {
        const email = `trigger_test_${uuidv4()}@test.com`;
        const password = 'Password123!';
        const companyName = `Trigger Org ${uuidv4()}`;

        const { data, error } = await supabase.auth.signUp({
            email,
            password,
            options: {
                data: {
                    full_name: 'Trigger User',
                    company_name: companyName
                }
            }
        });
        t.error(error, 'User should sign up');
        user = data.user;
        console.log('User signed up:', user.id);
        session = await loginUser(email, password);
        console.log('Session obtained, access token length:', session.access_token.length);


        const client = getClient(session.access_token);
        const { data: profile, error: profileErr } = await client.from('profiles').select('org_id, role_id').single();
        if (profileErr) console.error('Profile fetch error:', profileErr);
        orgId = profile?.org_id;
        roleId = profile?.role_id;
    });

    t.test('Metadata Trigger: set_rls_metadata', async (t) => {
        const client = getClient(session.access_token);

        const { data: company, error } = await client
            .from('crm_companies')
            .insert({ name: 'Auto Meta Company' })
            .select()
            .single();

        t.error(error, 'Should create company');
        t.equal(company.owner_user_id, user.id, 'owner_user_id should be set');
        t.equal(company.owner_tenant_id, orgId, 'owner_tenant_id should be set');
        t.equal(company.owner_role_id, roleId, 'owner_role_id should be set');
    });

    t.test('Signup Automation: Default data creation', async (t) => {
        const client = getClient(session.access_token);

        // Check Pipelines
        const { data: pipelines } = await client.from('crm_pipelines').select();
        t.ok(pipelines.length > 0, 'Default pipeline should be created');
        t.equal(pipelines[0].name, 'Sales Pipeline', 'Pipeline name should match');

        // Check Stages
        const { data: stages } = await client
            .from('crm_pipeline_stages')
            .select()
            .eq('pipeline_id', pipelines[0].id);
        t.equal(stages.length, 6, 'Should have 6 default stages');

        // Check Activity Types
        const { data: activityTypes } = await client.from('crm_activity_types').select();
        t.ok(activityTypes.length >= 5, 'Should have default activity types');
    });

    t.test('Hierarchy: rebuild_role_closure and cycle detection', async (t) => {
        // Create new roles
        const { data: roleA } = await supabaseAdmin
            .from('roles')
            .insert({ org_id: orgId, name: 'Manager' })
            .select()
            .single();

        const { data: roleB } = await supabaseAdmin
            .from('roles')
            .insert({ org_id: orgId, name: 'Lead' })
            .select()
            .single();

        // Create hierarchy: Owner -> Manager -> Lead
        await supabaseAdmin
            .from('role_hierarchy')
            .insert([
                { org_id: orgId, parent_role_id: roleId, child_role_id: roleA.id },
                { org_id: orgId, parent_role_id: roleA.id, child_role_id: roleB.id }
            ]);

        // Check closure
        const { data: closure } = await supabaseAdmin
            .from('role_closure')
            .select()
            .eq('parent_role_id', roleId)
            .eq('child_role_id', roleB.id);
        t.ok(closure.length > 0, 'Closure should contain Owner -> Lead');

        // Test Cycle Detection: Lead -> Owner (should fail)
        const { error: cycleError } = await supabaseAdmin
            .from('role_hierarchy')
            .insert({ org_id: orgId, parent_role_id: roleB.id, child_role_id: roleId });

        t.ok(cycleError, 'Cycle detection should prevent Lead -> Owner');
        t.match(cycleError.message, /Cyclic dependency detected/, 'Error message should match');
    });

    t.teardown(async () => {
        if (user) await deleteTestUser(user.id);
    });
});
