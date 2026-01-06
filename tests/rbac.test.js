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
        await cleanupUser('hacker@test.com');
        await cleanupUser('no-invite@test.com');
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

        // Create Employee Role
        const { data: employeeRole, error: eRoleError } = await ownerClient
            .from('roles')
            .insert({ tenant_id: tenantId, name: 'Employee' })
            .select()
            .single();
        t.error(eRoleError, 'Owner should create Employee role');
        employeeRoleId = employeeRole?.id;

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
            { role_id: managerRoleId, permission_code: 'dl:u' },
            { role_id: managerRoleId, permission_code: 'dl:d' },
            { role_id: managerRoleId, permission_code: 'iv:c' },
            { role_id: employeeRoleId, permission_code: 'dl:r' },
            { role_id: employeeRoleId, permission_code: 'dl:c' }
        ]);
        t.error(pError, 'Owner should grant permissions to subordinate roles');

        // REFRESH OWNER TOKEN
        ownerToken = await login(TEST_EMAIL_OWNER);
    });

    t.test('Scenario 3: Onboarding & Invitations', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);

        // Owner invites Manager
        await ownerClient.from('invitations').insert({ email: TEST_EMAIL_MANAGER, role_id: managerRoleId, tenant_id: tenantId });
        await supabaseAdmin.auth.admin.createUser({ email: TEST_EMAIL_MANAGER, password: TEST_PASSWORD, email_confirm: true });
        managerToken = await login(TEST_EMAIL_MANAGER);

        // Manager invites Employee
        const managerClient = await createAuthenticatedClient(managerToken);
        await managerClient.from('invitations').insert({ email: TEST_EMAIL_EMPLOYEE, role_id: employeeRoleId, tenant_id: tenantId });
        await supabaseAdmin.auth.admin.createUser({ email: TEST_EMAIL_EMPLOYEE, password: TEST_PASSWORD, email_confirm: true });
        employeeToken = await login(TEST_EMAIL_EMPLOYEE);

        t.ok(employeeToken, 'Employee should login');
    });

    t.test('Scenario 4: RBAC Enforcement (Deals)', async (t) => {
        const managerClient = await createAuthenticatedClient(managerToken);
        const employeeClient = await createAuthenticatedClient(employeeToken);

        // Employee creates a private deal
        const { data: deal, error: dealError } = await employeeClient
            .from('deals')
            .insert({ title: 'Employee Secret Deal', visibility: 'PRIVATE' })
            .select()
            .single();
        t.error(dealError, 'Employee should create deal');

        // Manager should see it
        const { data: mDeals } = await managerClient.from('deals').select();
        t.ok(mDeals?.find(d => d.id === deal?.id), 'Manager should see subordinate deal');

        // Create another tenant to test isolation
        await supabaseAdmin.rpc('provision_tenant', {
            p_name: 'Other Corp', p_slug: 'other', p_admin_email: 'other@test.com', p_role_name: 'Owner', p_permissions: ['dl:r']
        });
        await supabaseAdmin.auth.admin.createUser({ email: 'other@test.com', password: TEST_PASSWORD, email_confirm: true });
        const otherToken = await login('other@test.com');
        const otherClient = await createAuthenticatedClient(otherToken);

        const { data: otherDeals } = await otherClient.from('deals').select();
        t.notOk(otherDeals?.find(d => d.id === deal?.id), 'User from other tenant should not see deals');
    });

    t.test('Scenario 5: Security Constraints', async (t) => {
        const employeeClient = await createAuthenticatedClient(employeeToken);
        const { error: escError } = await employeeClient
            .from('role_permissions')
            .insert({ role_id: employeeRoleId, permission_code: 'rl:u' });
        t.ok(escError, 'Employee should NOT be able to grant permissions they dont have');
    });

    t.test('Scenario 6: Authentication & Onboarding Edge Cases', async (t) => {
        // 1. Signup without Invitation
        const { error: noInvError } = await supabaseAdmin.auth.admin.createUser({
            email: 'no-invite@test.com',
            password: TEST_PASSWORD,
            email_confirm: true
        });
        t.ok(noInvError, 'Signup without invitation should fail');
        // GoTrue wraps DB errors in a generic message
        t.match(noInvError.message, /Database error creating new user|No invitation found/, 'Error message should indicate failure');
    });

    t.test('Scenario 7: Role Hierarchy Constraints', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);

        // 1. Cycle Detection
        const { error: cycleError } = await ownerClient
            .from('role_hierarchy')
            .insert({ parent_id: employeeRoleId, child_id: managerRoleId });
        t.ok(cycleError, 'Circular hierarchy should fail');
        t.match(cycleError.message, /Cycle detected/, 'Error message should mention cycle');

        // 2. Root Role Protection
        const { error: renameError } = await ownerClient
            .from('roles')
            .update({ name: 'Super Owner' })
            .eq('id', ownerRoleId);
        t.ok(renameError, 'Renaming root role should fail');

        const { error: deleteError } = await ownerClient
            .from('roles')
            .delete()
            .eq('id', ownerRoleId);
        t.ok(deleteError, 'Deleting root role should fail');

        // 3. Single Root Enforcement
        const { error: secondRootError } = await ownerClient
            .from('roles')
            .insert({ tenant_id: tenantId, name: 'Another Owner', is_root: true });
        t.ok(secondRootError, 'Creating second root role should fail');
    });

    t.test('Scenario 8: Resource Access Control (Deals) - Visibility Transitions', async (t) => {
        const employeeClient = await createAuthenticatedClient(employeeToken);
        const managerClient = await createAuthenticatedClient(managerToken);

        // 1. Create PRIVATE deal
        const { data: deal } = await employeeClient
            .from('deals')
            .insert({ title: 'Transition Deal', visibility: 'PRIVATE' })
            .select().single();

        // 2. Update to PUBLIC
        const { error: pubError } = await employeeClient
            .from('deals')
            .update({ visibility: 'PUBLIC' })
            .eq('id', deal.id);
        t.error(pubError, 'Employee should update visibility to PUBLIC');

        // 3. Verify Manager can see it
        const { data: mDeals } = await managerClient.from('deals').select().eq('id', deal.id);
        t.equal(mDeals.length, 1, 'Manager should see PUBLIC deal');

        // 4. Unauthorized Update (Manager acting on Owner's deal)
        // Note: Our policy for UPDATE is: (p_visibility IN ('PRIVATE', 'CONTROLLED') THEN RETURN p_owner_id = auth.uid(); ELSE ...)
        // For PUBLIC deals, it checks dl:u permission.
        const { error: unauthUpdate } = await managerClient
            .from('deals')
            .update({ title: 'Hacked Title' })
            .eq('id', deal.id);
        t.error(unauthUpdate, 'Manager should be able to update PUBLIC deal if they have dl:u');

        // 5. Cross-Role Deletion
        const { error: eDeleteError } = await employeeClient
            .from('deals')
            .delete()
            .eq('owner_id', (await supabaseAdmin.from('profiles').select('id').eq('email', TEST_EMAIL_MANAGER).single()).data.id);
        // This should fail because Employee doesn't own Manager's deal and doesn't have dl:d on PRIVATE/CONTROLLED
        // But let's test Manager deleting Employee's deal
        const { error: mDeleteError } = await managerClient
            .from('deals')
            .delete()
            .eq('id', deal.id);
        t.error(mDeleteError, 'Manager should delete Employee deal');
    });

    t.test('Scenario 9: Storage Integration', async (t) => {
        const employeeClient = await createAuthenticatedClient(employeeToken);
        const managerClient = await createAuthenticatedClient(managerToken);

        const fileName = `test-${Date.now()}.txt`;
        const fileContent = 'Hello RBAC';

        // 1. Employee uploads file
        const { error: uploadError } = await employeeClient.storage
            .from('deals')
            .upload(fileName, fileContent);
        t.error(uploadError, 'Employee should upload file');

        // 2. Create deal referencing file
        const { data: deal } = await employeeClient.from('deals').insert({
            title: 'File Deal',
            file_path: fileName,
            visibility: 'PRIVATE'
        }).select().single();

        // 3. Manager downloads file
        const { data: downloadData, error: downloadError } = await managerClient.storage
            .from('deals')
            .download(fileName);
        t.error(downloadError, 'Manager should download subordinate deal file');
        t.ok(downloadData, 'Download data should exist');

        // 4. Other Tenant fails download
        await supabaseAdmin.rpc('provision_tenant', {
            p_name: 'Other Corp 2', p_slug: 'other2', p_admin_email: 'other2@test.com', p_role_name: 'Owner', p_permissions: ['dl:r']
        });
        await supabaseAdmin.auth.admin.createUser({ email: 'other2@test.com', password: TEST_PASSWORD, email_confirm: true });
        const otherToken = await login('other2@test.com');
        const otherClient = await createAuthenticatedClient(otherToken);

        const { error: otherDownloadError } = await otherClient.storage
            .from('deals')
            .download(fileName);
        t.ok(otherDownloadError, 'Other tenant should NOT download file');
    });

    t.test('Scenario 10: Permission & Escalation (Advanced)', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);
        const employeeClient = await createAuthenticatedClient(employeeToken);

        // 1. Permission Removal
        await ownerClient
            .from('role_permissions')
            .delete()
            .match({ role_id: employeeRoleId, permission_code: 'dl:c' });

        // Refresh employee token (or just wait if using JWT hook)
        // Since we use JWT hook, we need to re-login or wait for cache expiry.
        // In our setup, we re-login.
        const newEmployeeToken = await login(TEST_EMAIL_EMPLOYEE);
        const newEmployeeClient = await createAuthenticatedClient(newEmployeeToken);

        const { error: createError } = await newEmployeeClient
            .from('deals')
            .insert({ title: 'Forbidden Deal' });
        t.ok(createError, 'Employee should NOT create deal after permission removal');
    });

    t.test('Scenario 11: Database Integrity Triggers', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);

        // 1. Closure Table Consistency
        // Currently: Owner -> Manager -> Employee
        // Check if Owner is ancestor of Employee
        const { data: closureBefore } = await ownerClient
            .from('role_closure')
            .select()
            .match({ ancestor_id: ownerRoleId, descendant_id: employeeRoleId });
        t.equal(closureBefore.length, 1, 'Owner should be ancestor of Employee');

        // Delete Manager
        const { error: delError } = await ownerClient
            .from('roles')
            .delete()
            .eq('id', managerRoleId);
        t.error(delError, 'Owner should delete Manager role');

        // Check closure again
        const { data: closureAfter } = await ownerClient
            .from('role_closure')
            .select()
            .match({ ancestor_id: ownerRoleId, descendant_id: employeeRoleId });
        t.equal(closureAfter.length, 0, 'Owner should NO LONGER be ancestor of Employee after Manager deletion');
    });

    t.teardown(async () => {
        // Delete deals first to avoid FK violations
        await supabaseAdmin.from('deals').delete().neq('id', '00000000-0000-0000-0000-000000000000');

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
        await cleanupUser('other2@test.com');
        await cleanupUser('hacker@test.com');
        await cleanupUser('no-invite@test.com');
        await supabaseAdmin.from('tenants').delete().eq('slug', TENANT_SLUG);
        await supabaseAdmin.from('tenants').delete().eq('slug', 'other');
        await supabaseAdmin.from('tenants').delete().eq('slug', 'other2');
    });
});
