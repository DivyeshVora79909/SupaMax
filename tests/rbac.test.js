import { t } from 'tap';
import { supabaseAdmin, supabaseAnon, createAuthenticatedClient } from './setup.js';
import { decode } from 'jsonwebtoken';

const TEST_EMAIL_OWNER = 'owner@test.com';
const TEST_EMAIL_MANAGER = 'manager@test.com';
const TEST_EMAIL_EMPLOYEE = 'employee@test.com';
const TEST_PASSWORD = 'password123';
const TENANT_SLUG = 'test-tenant';

const logJwt = (token, label) => {
    const decoded = decode(token);
    console.log(`DEBUG: JWT [${label}]:`, JSON.stringify(decoded?.app_metadata, null, 2));
};

t.test('Multi-Tenant RBAC System Tests', async (t) => {
    let ownerToken, managerToken, employeeToken;
    let tenantId, ownerRoleId, managerRoleId, employeeRoleId;

    const login = async (email) => {
        const { data, error } = await supabaseAnon.auth.signInWithPassword({
            email,
            password: TEST_PASSWORD
        });
        if (error) {
            console.error(`Login failed for ${email}:`, error.message);
            throw error;
        }
        return data.session.access_token;
    };

    t.test('Scenario 1: Tenant Provisioning', async (t) => {
        // Cleanup first
        const cleanupUser = async (email) => {
            const { data } = await supabaseAdmin.from('profiles').select('id').eq('email', email).maybeSingle();
            if (data?.id) {
                await supabaseAdmin.auth.admin.deleteUser(data.id).catch(() => { });
            }
        };

        await cleanupUser(TEST_EMAIL_OWNER);
        await cleanupUser(TEST_EMAIL_MANAGER);
        await cleanupUser(TEST_EMAIL_EMPLOYEE);
        await cleanupUser('other@test.com');
        await supabaseAdmin.from('tenants').delete().eq('slug', TENANT_SLUG);
        await supabaseAdmin.from('tenants').delete().eq('slug', 'other');

        // Fetch all permissions
        const { data: allPerms } = await supabaseAdmin.from('permissions').select('code');
        const permCodes = allPerms.map(p => p.code);

        const { data, error } = await supabaseAdmin.rpc('provision_tenant', {
            p_name: 'Test Corp',
            p_slug: TENANT_SLUG,
            p_admin_email: TEST_EMAIL_OWNER,
            p_role_name: 'Owner',
            p_permissions: permCodes
        });

        t.error(error, 'Should provision tenant');
        tenantId = data?.tenant_id;
        ownerRoleId = data?.role_id;
        console.log('DEBUG: Tenant ID:', tenantId);
        console.log('DEBUG: Owner Role ID:', ownerRoleId);

        // Create Owner User
        const { error: uError } = await supabaseAdmin.auth.admin.createUser({
            email: TEST_EMAIL_OWNER,
            password: TEST_PASSWORD,
            email_confirm: true,
            user_metadata: { full_name: 'Test Owner' }
        });
        t.error(uError, 'Should create owner user');

        ownerToken = await login(TEST_EMAIL_OWNER);
        t.ok(ownerToken, 'Owner should login');
        logJwt(ownerToken, 'Owner');
    });

    t.test('Scenario 2: Role Hierarchy Setup', async (t) => {
        let ownerClient = await createAuthenticatedClient(ownerToken);

        // Create Manager Role
        const { data: managerRole, error: mRoleError } = await ownerClient
            .from('roles')
            .insert({ tenant_id: tenantId, name: 'Manager' })
            .select()
            .single();
        t.error(mRoleError, 'Owner should create Manager role');
        managerRoleId = managerRole?.id;
        console.log('DEBUG: Manager Role ID:', managerRoleId);

        // Create Employee Role
        const { data: employeeRole, error: eRoleError } = await ownerClient
            .from('roles')
            .insert({ tenant_id: tenantId, name: 'Employee' })
            .select()
            .single();
        t.error(eRoleError, 'Owner should create Employee role');
        employeeRoleId = employeeRole?.id;
        console.log('DEBUG: Employee Role ID:', employeeRoleId);

        // Establish Hierarchy: Owner -> Manager -> Employee
        const { error: h1Error } = await ownerClient
            .from('role_hierarchy')
            .insert({ parent_id: ownerRoleId, child_id: managerRoleId });
        t.error(h1Error, 'Owner should set Manager as child');

        const { error: h2Error } = await ownerClient
            .from('role_hierarchy')
            .insert({ parent_id: managerRoleId, child_id: employeeRoleId });
        t.error(h2Error, 'Owner should set Employee as child of Manager');

        // Grant Permissions
        const { error: pError } = await ownerClient.from('role_permissions').insert([
            { role_id: managerRoleId, permission_code: 'dl:r' },
            { role_id: managerRoleId, permission_code: 'dl:c' },
            { role_id: managerRoleId, permission_code: 'iv:c' },
            { role_id: employeeRoleId, permission_code: 'dl:r' },
            { role_id: employeeRoleId, permission_code: 'dl:c' }
        ]);
        t.error(pError, 'Owner should grant permissions to subordinate roles');

        // REFRESH OWNER TOKEN to get new subordinates in JWT
        ownerToken = await login(TEST_EMAIL_OWNER);
        logJwt(ownerToken, 'Owner (Refreshed)');
    });

    t.test('Scenario 3: Onboarding & Invitations', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);

        // Owner invites Manager
        const { error: invError } = await ownerClient
            .from('invitations')
            .insert({ email: TEST_EMAIL_MANAGER, role_id: managerRoleId, tenant_id: tenantId });
        t.error(invError, 'Owner should invite Manager');

        // Create Manager User
        const { error: mCreateError } = await supabaseAdmin.auth.admin.createUser({
            email: TEST_EMAIL_MANAGER,
            password: TEST_PASSWORD,
            email_confirm: true,
            user_metadata: { full_name: 'Test Manager' }
        });
        t.error(mCreateError, 'Should create manager user');

        managerToken = await login(TEST_EMAIL_MANAGER);
        t.ok(managerToken, 'Manager should login');
        logJwt(managerToken, 'Manager');

        // Manager invites Employee
        const managerClient = await createAuthenticatedClient(managerToken);
        const { error: inv2Error } = await managerClient
            .from('invitations')
            .insert({ email: TEST_EMAIL_EMPLOYEE, role_id: employeeRoleId, tenant_id: tenantId });
        t.error(inv2Error, 'Manager should invite Employee');

        // Create Employee User
        const { error: eCreateError } = await supabaseAdmin.auth.admin.createUser({
            email: TEST_EMAIL_EMPLOYEE,
            password: TEST_PASSWORD,
            email_confirm: true,
            user_metadata: { full_name: 'Test Employee' }
        });
        t.error(eCreateError, 'Should create employee user');

        employeeToken = await login(TEST_EMAIL_EMPLOYEE);
        t.ok(employeeToken, 'Employee should login');
        logJwt(employeeToken, 'Employee');
    });

    t.test('Scenario 4: RBAC Enforcement (Deals)', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);
        const managerClient = await createAuthenticatedClient(managerToken);
        const employeeClient = await createAuthenticatedClient(employeeToken);

        // Employee creates a private deal
        const { data: deal, error: dealError } = await employeeClient
            .from('deals')
            .insert({ title: 'Employee Secret Deal', visibility: 'PRIVATE' })
            .select()
            .single();
        t.error(dealError, 'Employee should create deal');

        // Verify deal details as Admin
        const { data: adminDeal } = await supabaseAdmin.from('deals').select('*').eq('id', deal?.id).single();
        console.log('DEBUG: Created Deal (Admin View):', JSON.stringify(adminDeal, null, 2));

        // Manager should see it (because they are an ancestor)
        const { data: mDeals } = await managerClient
            .from('deals')
            .select();
        t.ok(mDeals?.find(d => d.id === deal?.id), 'Manager should see subordinate deal');

        // Owner should see it
        const { data: oDeals } = await ownerClient
            .from('deals')
            .select();
        t.ok(oDeals?.find(d => d.id === deal?.id), 'Owner should see subordinate deal');

        // Create another tenant and user to test isolation
        const { data: otherData, error: otherProvError } = await supabaseAdmin.rpc('provision_tenant', {
            p_name: 'Other Corp',
            p_slug: 'other',
            p_admin_email: 'other@test.com',
            p_role_name: 'Owner',
            p_permissions: ['dl:r']
        });
        t.error(otherProvError, 'Should provision other tenant');

        const { error: otherUserError } = await supabaseAdmin.auth.admin.createUser({
            email: 'other@test.com',
            password: TEST_PASSWORD,
            email_confirm: true
        });
        t.error(otherUserError, 'Should create other user');

        const otherToken = await login('other@test.com');
        logJwt(otherToken, 'Other');
        const otherClient = await createAuthenticatedClient(otherToken);

        const { data: otherDeals } = await otherClient.from('deals').select();
        console.log('DEBUG: Deals visible to Other User:', JSON.stringify(otherDeals, null, 2));
        t.notOk(otherDeals?.find(d => d.id === deal?.id), 'User from other tenant should not see deals');
    });

    t.test('Scenario 5: Security Constraints', async (t) => {
        const employeeClient = await createAuthenticatedClient(employeeToken);

        // 1. Prevent Permission Escalation
        const { error: escError } = await employeeClient
            .from('role_permissions')
            .insert({ role_id: employeeRoleId, permission_code: 'rl:u' }); // Employee doesn't have rl:u
        t.ok(escError, 'Employee should NOT be able to grant permissions they dont have');

        // 2. Prevent Role Escalation in Invitations
        const { error: invEscError } = await employeeClient
            .from('invitations')
            .insert({ email: 'hacker@test.com', role_id: ownerRoleId, tenant_id: tenantId });
        t.ok(invEscError, 'Employee should NOT be able to invite to superior role');
    });

    t.teardown(async () => {
        const cleanupUser = async (email) => {
            const { data } = await supabaseAdmin.from('profiles').select('id').eq('email', email).maybeSingle();
            if (data?.id) {
                await supabaseAdmin.auth.admin.deleteUser(data.id).catch(() => { });
            }
        };
        await cleanupUser(TEST_EMAIL_OWNER);
        await cleanupUser(TEST_EMAIL_MANAGER);
        await cleanupUser(TEST_EMAIL_EMPLOYEE);
        await cleanupUser('other@test.com');
        await supabaseAdmin.from('tenants').delete().eq('slug', TENANT_SLUG);
        await supabaseAdmin.from('tenants').delete().eq('slug', 'other');
    });
});
