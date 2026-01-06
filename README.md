# SupaMax – Supabase Backend

Production‑grade, multi‑tenant Supabase backend with strict RBAC, hierarchical roles, secure storage, and policy‑driven access control.

---

## 1. Overview

SupaMax implements:

- **Multi‑tenancy** (tenant‑isolated data)
- **Hierarchical RBAC** (DAG‑based role tree)
- **JWT‑embedded permissions** (computed at login)
- **Strict RLS everywhere** (Postgres‑first security)
- **Controlled file storage** (Supabase Storage + DB‑backed authorization)

Designed for SaaS systems where **roles, permissions, and ownership matter**.

---

## 2. Architecture

**Core Layers**

- PostgreSQL (schema, RLS, triggers, functions)
- Supabase Auth (email‑invite onboarding)
- Supabase Storage (DB‑verified access)
- JWT Custom Claims (permissions, hierarchy)

**Security Model**

- No trust in frontend
- All access enforced at DB level
- Service Role only for provisioning

---

## 3. Key Concepts

### Tenant

Logical organization boundary. All data is tenant‑scoped.

### Roles

- One **root role** per tenant
- Roles form a **DAG** (not a tree)
- Closure table used for fast hierarchy queries

### Permissions

- Flat permission codes (`dl:c`, `rl:u`, etc.)
- Assigned to roles
- Injected into JWT at login

### Visibility Modes

```text
PRIVATE     → Owner only
CONTROLLED → Owner + subordinate roles
PUBLIC      → Permission‑based
```

---

## 4. Database Schema

### Core Tables

- `tenants`
- `roles`
- `permissions`
- `role_permissions`
- `role_hierarchy`
- `role_closure`
- `profiles`
- `invitations`
- `deals`

### Why Closure Table?

- O(1) permission checks
- Efficient subordinate resolution
- Prevents recursive runtime queries

---

## 5. Authentication Flow

1. User is **invited** (`invitations` table)
2. User signs up via Supabase Auth
3. `handle_new_user` trigger:

   - Validates invitation
   - Creates profile
   - Assigns tenant + role

No invitation → no access.

---

## 6. JWT Custom Claims

Injected via `custom_access_token_hook`:

```json
{
  "tenant_id": "uuid",
  "role_id": "uuid",
  "subordinate_role_ids": ["uuid"],
  "permissions": ["dl:c", "rl:u"]
}
```

Used by:

- RLS policies
- Access control functions

---

## 7. Access Control Engine

Central function:

```sql
check_resource_access(
  tenant_id,
  visibility,
  owner_id,
  owner_role_id,
  prefix,
  operation
)
```

Controls:

- SELECT / INSERT / UPDATE / DELETE
- Ownership
- Role hierarchy
- Explicit permissions

No duplicated logic in policies.

---

## 8. Row Level Security (RLS)

Enabled on **all tables**.

Examples:

- Tenants → self only
- Profiles → self or tenant
- Roles → tenant‑scoped + permission‑gated
- Deals → delegated to access engine

Service Role bypasses all checks.

---

## 9. Storage Security

Bucket: `deals`

Rules:

- Upload allowed only to `deals`
- Download/update/delete only if:

  - Matching DB record exists
  - User has access to that deal

Storage access is **DB‑verified**, not public.

---

## 10. Provisioning APIs

### Provision Tenant (Service Role)

```sql
rpc('provision_tenant', {
  p_name: 'Acme Corp',
  p_slug: 'acme',
  p_admin_email: 'admin@acme.com',
  p_role_name: 'Admin',
  p_permissions: ['dl:c','dl:r','dl:u','dl:d']
})
```

Creates:

- Tenant
- Root role
- Permissions
- Admin invitation

Atomic and secure.

---

## 11. Safety Guarantees

Enforced via triggers:

- No permission escalation
- No role escalation
- Single root per tenant
- Root role immutable
- DAG cycle prevention

Impossible to break hierarchy accidentally.

---

## 12. Local Development

```bash
supabase start
supabase stop
supabase db reset
supabase status
```

Service Logs:

| Service | Container                |
| ------- | ------------------------ |
| API     | supabase_kong_SupaMax    |
| DB      | supabase_db_SupaMax      |
| Auth    | supabase_auth_SupaMax    |
| Storage | supabase_storage_SupaMax |

---

## 13. Configuration Notes

- SMTP via SendGrid
- Auth email‑only
- Anonymous auth disabled
- Storage S3‑compatible

All secrets via environment variables.

---

## 14. Intended Use

Ideal for:

- B2B SaaS
- Internal enterprise tools
- Role‑heavy platforms
- Compliance‑sensitive systems

---

## 15. Philosophy

- Database is the authority
- JWTs are derived, not trusted
- UI is disposable
- Security is structural, not conditional

---

## 16. Example: End-to-End Tenant Bootstrap

### Provision tenant

```bash
SET LOCAL request.jwt.claim.role = 'service_role';

DO $$
DECLARE
    v_result json;
    v_email TEXT := 'div@gmail.com';
    v_password TEXT := 'password';
BEGIN
    -- A. Cleanup (Reset for fresh seed)
    DELETE FROM auth.users WHERE email = v_email;
    DELETE FROM public.tenants WHERE slug = 'acme';

    -- B. Provision Tenant Structure (Tenant, Role, Permissions, Invite)
    -- This uses the function defined in 04_logic.sql
    SELECT public.provision_tenant(
        'Acme Corp',
        'acme',
        v_email,
        'Owner',
        ARRAY(SELECT code FROM public.permissions) -- Grant ALL permissions
    ) INTO v_result;

    RAISE NOTICE 'Tenant Provisioned: %', v_result;

    -- C. Create Auth User (Simulate Invite Acceptance)
    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,

        -- CRITICAL FIX: Explicitly set tokens to empty strings instead of NULL.
        -- Supabase GoTrue crashes if these are NULL during manual insert.
        confirmation_token,
        recovery_token,
        email_change_token_new,
        email_change
    ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        gen_random_uuid(),
        'authenticated',
        'authenticated',
        v_email,
        crypt(v_password, gen_salt('bf')),
        now(),
        '{"provider": "email", "providers": ["email"]}',
        jsonb_build_object('full_name', 'Acme Admin'),
        now(),
        now(),

        -- FIX: Empty Strings
        '', '', '', ''
    );

    RAISE NOTICE 'User Created Successfully. Login with % / %', v_email, v_password;
END $$;

```
