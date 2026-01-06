import { t } from 'tap';
import { supabaseAdmin, supabaseAnon, createAuthenticatedClient } from './setup.js';
import { decode } from 'jsonwebtoken';

const TEST_EMAIL_OWNER = 'sub-owner@test.com';
const TEST_EMAIL_MANAGER = 'sub-manager@test.com';
const TEST_EMAIL_MANAGER_B = 'sub-manager-b@test.com';
const TEST_EMAIL_EMPLOYEE = 'sub-employee@test.com';
const TEST_PASSWORD = 'password123';
const TENANT_SLUG = 'sub-tenant';

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

t.test('Subscriber Perspective Integration Tests', async (t) => {
    let ownerToken, managerToken, managerBToken, employeeToken;
    let tenantId, ownerRoleId, managerRoleId, managerBRoleId, employeeRoleId;

    t.test('Setup: Provision Tenant and Users', async (t) => {
        // Cleanup
        const cleanupUser = async (email) => {
            const { data } = await supabaseAdmin.from('profiles').select('id').eq('email', email).maybeSingle();
            if (data?.id) {
                await supabaseAdmin.auth.admin.deleteUser(data.id).catch(() => { });
            }
        };
        await cleanupUser(TEST_EMAIL_OWNER);
        await cleanupUser(TEST_EMAIL_MANAGER);
        await cleanupUser(TEST_EMAIL_MANAGER_B);
        await cleanupUser(TEST_EMAIL_EMPLOYEE);
        await cleanupUser('other-owner@test.com');
        await supabaseAdmin.from('tenants').delete().eq('slug', TENANT_SLUG);
        await supabaseAdmin.from('tenants').delete().eq('slug', 'other-tenant');

        // 1. Provision Tenant A
        const { data: provData, error: provError } = await supabaseAdmin.rpc('provision_tenant', {
            p_name: 'Subscriber Corp',
            p_slug: TENANT_SLUG,
            p_admin_email: TEST_EMAIL_OWNER,
            p_role_name: 'Owner'
        });
        t.error(provError, 'Should provision tenant');
        tenantId = provData.tenant_id;
        ownerRoleId = provData.role_id;

        // 2. Create Owner User
        await supabaseAdmin.auth.admin.createUser({
            email: TEST_EMAIL_OWNER,
            password: TEST_PASSWORD,
            email_confirm: true
        });
        ownerToken = await login(TEST_EMAIL_OWNER);

        // 3. Create Manager and Employee via Invitations (to get profiles)
        const ownerClient = await createAuthenticatedClient(ownerToken);

        // Create Manager Role (Standard INSERT)
        const { data: mRole } = await ownerClient.from('roles').insert({ name: 'Manager' }).select().single();
        managerRoleId = mRole.id;

        // Create Manager B Role
        const { data: mbRole } = await ownerClient.from('roles').insert({ name: 'Manager B' }).select().single();
        managerBRoleId = mbRole.id;

        // Create Employee Role (Standard INSERT)
        const { data: eRole } = await ownerClient.from('roles').insert({ name: 'Employee' }).select().single();
        employeeRoleId = eRole.id;

        // Establish Hierarchy: Owner -> Manager -> Employee, Owner -> Manager B
        await ownerClient.from('role_hierarchy').insert([
            { parent_id: ownerRoleId, child_id: managerRoleId },
            { parent_id: managerRoleId, child_id: employeeRoleId },
            { parent_id: ownerRoleId, child_id: managerBRoleId }
        ]);

        // Grant Permissions to Manager, Manager B, and Employee BEFORE they login
        await ownerClient.from('role_permissions').insert([
            { role_id: managerRoleId, permission_code: 'dl:r' },
            { role_id: managerRoleId, permission_code: 'dl:c' },
            { role_id: managerRoleId, permission_code: 'dl:u' },
            { role_id: managerRoleId, permission_code: 'dl:d' },
            { role_id: managerRoleId, permission_code: 'iv:c' },
            { role_id: managerBRoleId, permission_code: 'dl:r' },
            { role_id: managerBRoleId, permission_code: 'dl:c' },
            { role_id: managerBRoleId, permission_code: 'dl:u' },
            { role_id: managerBRoleId, permission_code: 'dl:d' },
            { role_id: managerBRoleId, permission_code: 'iv:c' },
            { role_id: employeeRoleId, permission_code: 'dl:r' },
            { role_id: employeeRoleId, permission_code: 'dl:c' }
        ]);

        // Invite Manager
        await ownerClient.rpc('invite_user_secure', { p_email: TEST_EMAIL_MANAGER, p_role_id: managerRoleId });
        await supabaseAdmin.auth.admin.createUser({ email: TEST_EMAIL_MANAGER, password: TEST_PASSWORD, email_confirm: true });
        managerToken = await login(TEST_EMAIL_MANAGER);

        // Invite Manager B (Sibling of Manager)
        await ownerClient.rpc('invite_user_secure', { p_email: TEST_EMAIL_MANAGER_B, p_role_id: managerBRoleId });
        await supabaseAdmin.auth.admin.createUser({ email: TEST_EMAIL_MANAGER_B, password: TEST_PASSWORD, email_confirm: true });
        managerBToken = await login(TEST_EMAIL_MANAGER_B);

        // Invite Employee
        await ownerClient.rpc('invite_user_secure', { p_email: TEST_EMAIL_EMPLOYEE, p_role_id: employeeRoleId });
        await supabaseAdmin.auth.admin.createUser({ email: TEST_EMAIL_EMPLOYEE, password: TEST_PASSWORD, email_confirm: true });
        employeeToken = await login(TEST_EMAIL_EMPLOYEE);

        t.ok(ownerToken && managerToken && managerBToken && employeeToken, 'All users should be logged in');
    });

    t.test('Scenario 1: Role & Permission Management (REST)', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);
        const managerClient = await createAuthenticatedClient(managerToken);

        // 1. Owner creates a new role via standard INSERT
        const { data: newRole, error: roleError } = await ownerClient
            .from('roles')
            .insert({ name: 'Specialist' })
            .select()
            .single();
        t.error(roleError, 'Owner should create role via REST');
        t.equal(newRole.tenant_id, tenantId, 'Trigger should auto-populate tenant_id');

        // 2. Owner grants permission via standard INSERT
        const { error: permError } = await ownerClient
            .from('role_permissions')
            .insert({ role_id: newRole.id, permission_code: 'dl:r' });
        t.error(permError, 'Owner should grant permission via REST');

        // 3. Manager attempts to grant permission they DON'T have
        // Manager has: dl:r, dl:c, dl:u, dl:d, iv:c

        // Now Manager tries to grant 'tn:u' (Tenant Update) which they don't have.
        const { error: escalationError } = await managerClient
            .from('role_permissions')
            .insert({ role_id: employeeRoleId, permission_code: 'tn:u' });
        t.ok(escalationError, 'Manager should NOT grant permission they do not possess');
        t.match(escalationError.message, /Access Denied/, 'Error should mention Access Denied');
    });

    t.test('Scenario 2: Hierarchy Management (REST)', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);
        const managerClient = await createAuthenticatedClient(managerToken);

        // 1. Owner (Root) should modify hierarchy via REST
        // We already established Owner -> Manager -> Employee in setup.
        // Let's just verify it exists.
        const { data: hierarchy } = await ownerClient
            .from('role_hierarchy')
            .select()
            .match({ parent_id: managerRoleId, child_id: employeeRoleId });
        t.ok(hierarchy.length > 0, 'Hierarchy should exist');

        // 2. Manager (Non-Root) attempts to modify hierarchy via REST
        const { error: hUnauthError } = await managerClient
            .from('role_hierarchy')
            .insert({ parent_id: ownerRoleId, child_id: managerRoleId }); // This is also circular but RLS should hit first
        t.ok(hUnauthError, 'Manager (Non-Root) should be blocked by RLS from modifying hierarchy');
    });

    t.test('Scenario 3: Resource Management (REST)', async (t) => {
        const managerClient = await createAuthenticatedClient(managerToken);
        const employeeClient = await createAuthenticatedClient(employeeToken);

        // 1. Manager creates deal via REST
        const { data: deal, error: dealError } = await managerClient
            .from('deals')
            .insert({ title: 'Manager Deal' })
            .select()
            .single();
        t.error(dealError, 'Manager should create deal via REST');
        t.equal(deal.tenant_id, tenantId, 'Trigger should auto-populate tenant_id');
        t.equal(deal.owner_role_id, managerRoleId, 'Trigger should auto-populate owner_role_id');

        // 2. Employee attempts unauthorized update on Manager's deal
        const { error: updateError } = await employeeClient
            .from('deals')
            .update({ title: 'Hacked' })
            .eq('id', deal.id);
        // RLS should block this because Employee doesn't own it and it's PRIVATE
        const { data: checkDeal } = await managerClient.from('deals').select('title').eq('id', deal.id).single();
        t.equal(checkDeal.title, 'Manager Deal', 'Employee should NOT update Manager deal');
    });

    t.test('Scenario 4: Multi-Tenant Isolation (REST)', async (t) => {
        // 1. Setup Tenant B
        const OTHER_OWNER = 'other-owner@test.com';
        const { data: provB } = await supabaseAdmin.rpc('provision_tenant', {
            p_name: 'Other Corp',
            p_slug: 'other-tenant',
            p_admin_email: OTHER_OWNER,
            p_role_name: 'Owner'
        });
        await supabaseAdmin.auth.admin.createUser({ email: OTHER_OWNER, password: TEST_PASSWORD, email_confirm: true });
        const otherToken = await login(OTHER_OWNER);
        const otherClient = await createAuthenticatedClient(otherToken);

        const ownerClient = await createAuthenticatedClient(ownerToken);

        // 2. Tenant A Owner attempts to read Tenant B roles
        const { data: otherRoles } = await ownerClient.from('roles').select().eq('tenant_id', provB.tenant_id);
        t.equal(otherRoles.length, 0, 'Tenant A should NOT see Tenant B roles');

        // 3. Tenant A Owner attempts to insert into Tenant B
        const { error: crossInsertError } = await ownerClient
            .from('roles')
            .insert({ name: 'Ghost Role', tenant_id: provB.tenant_id });
        // RLS should block this because is_in_my_tenant(provB.tenant_id) is false.
        t.ok(crossInsertError, 'Cross-tenant insert should be blocked by RLS');

        // 4. Tenant A Owner attempts to insert WITHOUT tenant_id (Trigger should handle it)
        const { data: autoRole, error: autoError } = await ownerClient
            .from('roles')
            .insert({ name: 'Auto Role' })
            .select()
            .single();
        t.error(autoError, 'Insert without tenant_id should succeed (Trigger handles it)');
        t.equal(autoRole.tenant_id, tenantId, 'Trigger should auto-populate tenant_id');
    });

    t.test('Scenario 5: Role Deletion & Integrity (REST)', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);

        // 1. Create a role and hierarchy
        const { data: tempRole } = await ownerClient.from('roles').insert({ name: 'Temp Role' }).select().single();
        await ownerClient.from('role_hierarchy').insert({ parent_id: employeeRoleId, child_id: tempRole.id });

        // Verify closure
        const { data: closure } = await ownerClient.from('role_closure').select().match({ ancestor_id: managerRoleId, descendant_id: tempRole.id });
        t.equal(closure.length, 1, 'Closure should exist before deletion');

        // 2. Delete role via REST
        const { error: delError } = await ownerClient.from('roles').delete().eq('id', tempRole.id);
        t.error(delError, 'Owner should delete role via REST');

        // 3. Verify integrity
        const { data: closureAfter } = await ownerClient.from('role_closure').select().match({ descendant_id: tempRole.id });
        t.equal(closureAfter.length, 0, 'Closure should be cleaned up');

        const { data: hierarchyAfter } = await ownerClient.from('role_hierarchy').select().eq('child_id', tempRole.id);
        t.equal(hierarchyAfter.length, 0, 'Hierarchy should be cleaned up (CASCADE)');
    });

    t.test('Scenario 6: Invitation via REST', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);
        const managerClient = await createAuthenticatedClient(managerToken);

        // 1. Owner creates invitation via standard INSERT
        const { data: invite, error: inviteError } = await ownerClient
            .from('invitations')
            .insert({
                email: 'new-user@test.com',
                role_id: employeeRoleId
            })
            .select()
            .single();
        t.error(inviteError, 'Owner should create invitation via REST');
        t.equal(invite.tenant_id, tenantId, 'Trigger should auto-populate tenant_id');
        t.ok(invite.invited_by, 'Trigger should auto-populate invited_by');

        // 2. Manager attempts to invite an Owner (Escalation)
        const { error: escalationError } = await managerClient
            .from('invitations')
            .insert({
                email: 'hacker-owner@test.com',
                role_id: ownerRoleId
            });
        t.ok(escalationError, 'Manager should NOT invite Owner via REST (Escalation)');
        t.match(escalationError.message, /Access Denied/, 'Error should mention Access Denied');
    });

    t.test('Scenario 7: Hierarchy Data Visibility (Downward Look)', async (t) => {
        const managerClient = await createAuthenticatedClient(managerToken);
        const managerBClient = await createAuthenticatedClient(managerBToken);
        const employeeClient = await createAuthenticatedClient(employeeToken);

        // 1. Employee creates a PRIVATE deal
        const { data: empDeal } = await employeeClient.from('deals').insert({ title: 'Employee Private', visibility: 'PRIVATE' }).select().single();

        // 2. Manager (Superior) should see it
        const { data: seenByManager } = await managerClient.from('deals').select().eq('id', empDeal.id).maybeSingle();
        t.ok(seenByManager, 'Manager should see subordinate PRIVATE deal');

        // 3. Manager B (Sibling) should NOT see it
        const { data: seenByManagerB } = await managerBClient.from('deals').select().eq('id', empDeal.id).maybeSingle();
        t.notOk(seenByManagerB, 'Sibling Manager should NOT see other branch PRIVATE deal');

        // 4. Employee should NOT see Manager's PRIVATE deal
        const { data: mgrDeal } = await managerClient.from('deals').insert({ title: 'Manager Private', visibility: 'PRIVATE' }).select().single();
        const { data: seenByEmployee } = await employeeClient.from('deals').select().eq('id', mgrDeal.id).maybeSingle();
        t.notOk(seenByEmployee, 'Employee should NOT see superior PRIVATE deal');
    });

    t.test('Scenario 8: ID Spoofing & Data Integrity', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);
        const employeeClient = await createAuthenticatedClient(employeeToken);

        // 1. Setup Tenant B
        const OTHER_OWNER = 'other-owner@test.com';
        const { data: provB } = await supabaseAdmin.rpc('provision_tenant', {
            p_name: 'Other Corp',
            p_slug: 'other-tenant-b',
            p_admin_email: OTHER_OWNER,
            p_role_name: 'Owner'
        });

        // 2. Tenant A Owner tries to create a Role using a parent_id belonging to Tenant B
        const { error: spoofError } = await ownerClient
            .from('role_hierarchy')
            .insert({ parent_id: provB.role_id, child_id: employeeRoleId });
        t.ok(spoofError, 'Should block hierarchy insertion with cross-tenant parent_id');

        // 3. User attempts to UPDATE their own profile to change their role_id to Owner
        const { data: myProfile } = await employeeClient.from('profiles').select().eq('email', TEST_EMAIL_EMPLOYEE).single();
        const { error: promoError } = await employeeClient
            .from('profiles')
            .update({ role_id: ownerRoleId })
            .eq('id', myProfile.id);
        // RLS or Trigger should block this. 
        // Actually, we don't have a specific policy/trigger blocking role_id update yet, 
        // but let's see if it fails or we need to add one.

        // Check if role_id actually changed
        const { data: checkProfile } = await supabaseAdmin.from('profiles').select('role_id').eq('id', myProfile.id).single();
        t.equal(checkProfile.role_id, employeeRoleId, 'Employee should NOT be able to self-promote');
    });

    t.test('Scenario 9: Business Logic & Visibility Transitions', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);
        const employeeClient = await createAuthenticatedClient(employeeToken);
        const managerBClient = await createAuthenticatedClient(managerBToken);

        // 1. Employee creates a PUBLIC deal
        const { data: pubDeal } = await employeeClient.from('deals').insert({ title: 'Public Deal', visibility: 'PUBLIC' }).select().single();

        // 2. Manager B (Sibling) should see it
        const { data: seenByB } = await managerBClient.from('deals').select().eq('id', pubDeal.id).maybeSingle();
        t.ok(seenByB, 'Sibling should see PUBLIC deal');

        // 3. Owner changes deal from PUBLIC to PRIVATE
        const { error: updateError } = await ownerClient.from('deals').update({ visibility: 'PRIVATE' }).eq('id', pubDeal.id);
        t.error(updateError, 'Owner should update deal visibility');

        // Verify it is actually PRIVATE
        const { data: checkDeal } = await supabaseAdmin.from('deals').select('visibility').eq('id', pubDeal.id).single();
        t.equal(checkDeal.visibility, 'PRIVATE', 'Deal should be PRIVATE');

        // 4. Manager B should NO LONGER see it
        const { data: seenByBAfter } = await managerBClient.from('deals').select().eq('id', pubDeal.id).maybeSingle();
        t.notOk(seenByBAfter, 'Sibling should lose access after visibility change to PRIVATE');
    });

    t.test('Scenario 10: Storage Security (S3/Files)', async (t) => {
        const managerClient = await createAuthenticatedClient(managerToken);
        const managerBClient = await createAuthenticatedClient(managerBToken);

        const fileName = `test-file-${Date.now()}.txt`;
        const fileContent = 'Hello World';

        // 1. Manager uploads a file linked to a Private Deal
        const { data: privDeal } = await managerClient.from('deals').insert({ title: 'Storage Deal', visibility: 'PRIVATE', file_path: fileName }).select().single();

        const { error: uploadError } = await managerClient.storage.from('deals').upload(fileName, fileContent);
        t.error(uploadError, 'Manager should upload file');

        // 2. Manager B (who cannot see the Deal) tries to download it
        const { data: downloadData, error: downloadError } = await managerBClient.storage.from('deals').download(fileName);
        t.ok(downloadError, 'Manager B should be blocked from downloading file of PRIVATE deal they cannot see');
    });

    t.test('Scenario 11: Permission Boundaries', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);
        const employeeClient = await createAuthenticatedClient(employeeToken);

        // 1. Owner removes dl:c (Create Deal) from the "Employee" role
        await ownerClient.from('role_permissions').delete().match({ role_id: employeeRoleId, permission_code: 'dl:c' });

        // 2. Employee tries to create a deal
        // Note: Token refresh is a separate concern, but the DB check (has_permission) should hit the DB.
        // Our has_permission function checks the JWT first, then the DB if claims are missing.
        // If the token is NOT refreshed, it might still have the claim.
        // However, RLS policies use public.has_permission('dl:c') which we should ensure checks the DB or we force a refresh.
        // In this test, we'll just check if it fails.
        const { error: createError } = await employeeClient.from('deals').insert({ title: 'Should Fail' });
        t.ok(createError, 'Employee should be blocked from creating deal after permission revocation');

        // 3. Tenant Owner tries to INSERT into public.permissions
        const { error: sysError } = await ownerClient.from('permissions').insert({ code: 'xx:x', name: 'Hacker Perm' });
        t.ok(sysError, 'Tenant Owner should NOT define new system-wide permissions');
    });

    t.test('Scenario 12: Destructive Actions', async (t) => {
        const ownerClient = await createAuthenticatedClient(ownerToken);

        // 1. Tenant Owner tries to DELETE their own Role (The Root Role)
        const { error: suicideError } = await ownerClient.from('roles').delete().eq('id', ownerRoleId);
        t.ok(suicideError, 'Owner should NOT delete their own Root Role');

        // 2. Owner tries to DELETE a Role that still has active Users assigned to it (Manager)
        const { error: orphanError } = await ownerClient.from('roles').delete().eq('id', managerRoleId);
        t.ok(orphanError, 'Should block deletion of role with active users (FK Constraint)');
    });

    t.teardown(async () => {
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
        await cleanupUser('other-owner@test.com');
        await supabaseAdmin.from('tenants').delete().eq('slug', TENANT_SLUG);
        await supabaseAdmin.from('tenants').delete().eq('slug', 'other-tenant');
    });
});
