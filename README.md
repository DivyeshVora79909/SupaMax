# SupaMax

A hierarchical, permission-based access control system and CRM built on Supabase. SupaMax implements a Directed Acyclic Graph (DAG) structure for organizational management with granular role-based permissions and a complete CRM suite.

## Architecture Overview

### Core Concepts

- **DAG Structure**: Uses a closure table pattern (`closure_dominance`) for efficient tree traversal and dominance queries.
- **Node Types**:
  - `user` - Authenticated users with Supabase Auth linkage.
  - `group` - Organizational containers (companies, teams, departments).
  - `role` - Permission carriers with 256-bit permission bitmaps.
- **Permission System**: 256-bit bitmap allowing for fine-grained capability control.
- **Dominance Model**: Parent nodes control child nodes; permissions flow downward through roles.

## Database Schema

### Core Graph Tables

| Table                 | Purpose                                                        |
| :-------------------- | :------------------------------------------------------------- |
| `dag_node`            | Stores users, groups, and roles with type-specific constraints |
| `dag_edge`            | Parent-child relationships forming the DAG                     |
| `closure_dominance`   | Transitive closure for O(1) dominance checks                   |
| `permission_manifest` | Maps permission slugs to bit indices (0-255)                   |

### CRM Module Tables

| Table                  | Purpose                                       |
| :--------------------- | :-------------------------------------------- |
| `crm_label`            | Configurable labels/statuses for CRM entities |
| `account`              | Company/organization records                  |
| `contact`              | People associated with accounts               |
| `opportunity`          | Sales opportunities linked to accounts        |
| `project`              | Projects derived from opportunities           |
| `opportunity_activity` | Audit log for opportunity changes             |

## Security Model

### Row Level Security (RLS)

All tables use RLS policies based on:

1. **Permission checks** - User must have specific capability bit set.
2. **Dominance checks** - User must dominate (be ancestor of) the resource owner.
3. **Membership checks** - User must belong to the same group/role hierarchy.

### Key Security Functions

- `get_graph_context()` - Returns current user's node ID, effective permissions, and memberships.
- `assert_dominance()` - Validates actor controls target node.
- `assert_permission()` - Validates actor has specific permission.
- `assert_no_escalation()` - Prevents privilege escalation when assigning permissions.

## API Functions

### Graph Management

| Function                                        | Permission Required          | Description                          |
| :---------------------------------------------- | :--------------------------- | :----------------------------------- |
| `rpc_create_group(parent_id, label)`            | `NODE_CREATE`                | Create new group under parent        |
| `rpc_create_role(parent_id, label, bits)`       | `NODE_CREATE`, `ROLE_MANAGE` | Create role with permission set      |
| `rpc_link_node(parent, child)`                  | `EDGE_LINK`                  | Create edge between existing nodes   |
| `rpc_unlink_node(parent, child)`                | `EDGE_UNLINK`                | Remove edge (prevents orphans)       |
| `rpc_delete_node(target_id)`                    | `NODE_DELETE`                | Delete leaf node only                |
| `rpc_invite_user(parent_id, label, expires_in)` | `NODE_CREATE`                | Generate invite token for new user   |
| `rpc_claim_invite(token)`                       | -                            | Convert invite to authenticated user |

### Context Helpers

- `current_node_id()` - Get UUID of current auth user in graph.
- `get_client_context()` - JSON context for frontend consumption.
- `get_perm_id(slug)` - Resolve permission slug to bit index.

## Permission Reference

### Graph Structure (0-10)

| Bit | Slug          | Description           |
| :-- | :------------ | :-------------------- |
| 0   | `GRAPH_READ`  | View graph structure  |
| 1   | `NODE_CREATE` | Create nodes          |
| 2   | `NODE_DELETE` | Delete leaf nodes     |
| 3   | `EDGE_LINK`   | Link nodes            |
| 4   | `EDGE_UNLINK` | Unlink nodes          |
| 10  | `ROLE_MANAGE` | Edit role permissions |

### CRM Configuration (31-33)

| Bit | Slug               | Description   |
| :-- | :----------------- | :------------ |
| 31  | `CRM_LABEL_INSERT` | Create labels |
| 32  | `CRM_LABEL_UPDATE` | Update labels |
| 33  | `CRM_LABEL_DELETE` | Delete labels |

### Account (40-43)

| Bit | Slug             | Description     |
| :-- | :--------------- | :-------------- |
| 40  | `ACCOUNT_SELECT` | View accounts   |
| 41  | `ACCOUNT_INSERT` | Create accounts |
| 42  | `ACCOUNT_UPDATE` | Edit accounts   |
| 43  | `ACCOUNT_DELETE` | Delete accounts |

### Contact (50-53)

| Bit | Slug             | Description     |
| :-- | :--------------- | :-------------- |
| 50  | `CONTACT_SELECT` | View contacts   |
| 51  | `CONTACT_INSERT` | Create contacts |
| 52  | `CONTACT_UPDATE` | Edit contacts   |
| 53  | `CONTACT_DELETE` | Delete contacts |

### Opportunity (60-66)

| Bit | Slug                  | Description          |
| :-- | :-------------------- | :------------------- |
| 60  | `OPP_SELECT`          | View opportunities   |
| 61  | `OPP_INSERT`          | Create opportunities |
| 62  | `OPP_UPDATE`          | Edit opportunities   |
| 63  | `OPP_DELETE`          | Delete opportunities |
| 64  | `OPP_ACTIVITY_INSERT` | Log activities       |
| 65  | `OPP_ACTIVITY_UPDATE` | Edit activities      |
| 66  | `OPP_ACTIVITY_DELETE` | Delete activities    |

### Project (70-73)

| Bit | Slug          | Description     |
| :-- | :------------ | :-------------- |
| 70  | `PROJ_SELECT` | View projects   |
| 71  | `PROJ_INSERT` | Create projects |
| 72  | `PROJ_UPDATE` | Edit projects   |
| 73  | `PROJ_DELETE` | Delete projects |

---

## Local Development

### Prerequisites

- Supabase CLI installed (`npm install -g supabase` or `brew install supabase`)
- Docker (for local Postgres/Supabase services)
- Node.js environment (for edge functions if applicable)

### Initialize Project

```bash
# Login to Supabase
supabase login

# Initialize (if starting fresh)
supabase init

# Start local stack (Postgres, Auth, Storage, Edge Functions, etc.)
supabase start

# Check status of all services
supabase status
```

### Database Commands

```bash
# Start local database only
supabase db start

# Stop local database
supabase db stop

# Reset local database (wipes data, reapplies all migrations + seed)
supabase db reset

# Lint database schema for issues
supabase db lint

# Dump schema only (for backup/inspection)
supabase db dump --schema-only > schema_backup.sql

# Dump data only (for data migration)
supabase db dump --data-only > data_backup.sql
```

### Migration Workflow

```bash
# Create a new empty migration file
supabase migration new add_crm_invoice_table

# Generate migration from schema diff (local vs target)
supabase db diff -f schema_changes

# List all migrations and their status
supabase migration list

# Apply pending migrations to local database
supabase migration up

# Apply specific migration (up or down)
supabase migration up --target 0001001_schema
```

### Schema Sync (Pull/Push)

```bash
# Link to remote project (required for push/pull)
supabase link --project-ref <your-project-ref>

# Pull remote schema changes into a new migration file
supabase db pull remote_changes

# Push local migrations to remote database
supabase db push

# Push with password (if not using interactive auth)
supabase db push --password <your-db-password>
```

**Important Notes on Push/Pull:**

- `db push` applies pending migrations (new ones not in remote history) — it doesn't sync schema 1:1.
- `db pull` creates a migration file from remote schema drift — doesn't modify your local DB.
- Migrations are tracked in Postgres `supabase_migrations.schema_migrations` table.
- Migration files in `supabase/migrations/` are for version control only.

### Edge Functions

```bash
# Create new Edge Function
supabase functions new my-function

# Serve functions locally (hot reload)
supabase functions serve

# Deploy function to remote
supabase functions deploy my-function

# Deploy all functions
supabase functions deploy
```

### Type Generation

```bash
# Generate TypeScript types from local database schema
supabase gen types typescript --local > types/database.ts

# Generate types from linked remote project
supabase gen types typescript --linked > types/database.ts

# Generate types from specific project (no linking required)
supabase gen types typescript --project-id <project-ref> > types/database.ts
```

### Storage Management

```bash
# List storage buckets
supabase storage ls

# Copy file to storage
supabase storage cp ./local-file.png bucket/path/to/file.png

# Move/rename storage object
supabase storage mv bucket/old.png bucket/new.png

# Delete storage object
supabase storage rm bucket/file.png
```

### Testing & Inspection

```bash
# Open SQL editor connected to local database
supabase sql

# Run specific SQL file
supabase sql < queries/test.sql

# Execute command directly
supabase sql "SELECT * FROM dag_node LIMIT 5;"

# Inspect database (opens psql)
supabase inspect db
```

---

## Deployment

### Production Deployment

```bash
# 1. Ensure you're logged in and linked
supabase login
supabase link --project-ref <your-project-ref>

# 2. Test migrations locally first
supabase db reset

# 3. Push to production
supabase db push

# 4. Deploy edge functions
supabase functions deploy

# 5. Verify status
supabase status
```

---

## Migration Safety

| Operation           | Data Impact                      | Safe?          |
| :------------------ | :------------------------------- | :------------- |
| Add column          | Data preserved (NULL/default)    | ✅ Yes         |
| Rename column/table | Data preserved (metadata change) | ✅ Yes         |
| Add RLS/Policy      | No data change                   | ✅ Yes         |
| Add trigger         | No existing data change          | ✅ Yes         |
| Delete column       | Data lost permanently            | ⚠️ Danger      |
| Alter column type   | Risky (cast dependent)           | ⚠️ Check first |
| Drop table          | All data lost                    | ❌ Destructive |

**Safe Migration Patterns:**

```sql
-- Add nullable column first
ALTER TABLE users ADD COLUMN phone text;

-- Backfill data if needed
UPDATE users SET phone = '' WHERE phone IS NULL;

-- Add constraint later
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
```

---

## Troubleshooting

```bash
# View logs
supabase logs

# Restart services
supabase stop && supabase start

# Full reset (nuclear option)
supabase stop
docker volume rm supabase_db  # removes Postgres data
supabase start

# Check CLI version
supabase --version

# Update CLI
npm update -g supabase
```

---

## Project Structure

```text
supabase/
├── migrations/           # SQL migration files (timestamped)
│   ├── 0001001_schema.sql
│   ├── 0001002_context.sql
│   └── 0009001_seed.sql
├── functions/            # Edge Functions (TypeScript)
├── config.toml           # Local Supabase configuration
└── seed.sql              # Optional: default seed data
```

---

## Key Concepts for Migrations

- **Migration Files:** SQL scripts in `supabase/migrations/` tracked by Git.
- **Migration History:** Postgres table tracking which migrations ran.
- **Idempotency:** Use `IF NOT EXISTS` / `ON CONFLICT DO NOTHING` for safety.
- **Push vs Reset:**
  - `db push` = apply new migrations to existing DB.
  - `db reset` = wipe everything, start fresh with all migrations.

supabase db reset --linked
supabase projects list

crons required:
partioning audit log monthly
orphan node and edge cleanup
object storage cleanup
