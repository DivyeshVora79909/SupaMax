# SupaMax

A hierarchical, permission-based access control system and CRM built on Supabase. SupaMax implements a Directed Acyclic Graph (DAG) structure for organizational management with granular role-based permissions and a complete CRM suite.

### Core Graph Tables

| Table                 | Purpose                                                        |
| :-------------------- | :------------------------------------------------------------- |
| `dag_node`            | Stores users, groups, and roles with type-specific constraints |
| `dag_edge`            | Parent-child relationships forming the DAG                     |
| `closure_dominance`   | Transitive closure for O(1) dominance checks                   |
| `permission_manifest` | Maps permission slugs to bit indices (0-255)                   |

### Core Concepts

- **Node Types**:
  - `user` - Authenticated users with Supabase Auth linkage.
  - `group` - Organizational containers (companies, teams, departments).
  - `role` - Permission carriers with 256-bit permission bitmaps.

### Row Level Security (RLS)

All tables use RLS policies based on:

1. **Permission checks** - User must have specific capability bit set.
2. **Dominance checks** - User must dominate (be ancestor of) the resource owner.
3. **Membership checks** - User must belong to the same group/role hierarchy.

### Prerequisites

- Supabase CLI installed (`npm install -g supabase` or `brew install supabase`)
- Docker (for local Postgres/Supabase services)
- Node.js environment (for edge functions if applicable)

### Initialize Project

```bash
supabase login
supabase init
supabase start
supabase status
supabase projects list
```

### Database Commands

```bash
supabase db start
supabase db stop
supabase db reset
supabase db reset --linked
```

### Schema Sync (Pull/Push)

```bash
supabase link --project-ref <your-project-ref>
supabase db pull remote_changes
supabase db push
supabase db push --password <your-db-password>
```

### Edge Functions

```bash
supabase functions new my-function
supabase functions serve
supabase functions deploy my-function
supabase functions deploy
```

### Production Deployment

```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase db reset
supabase db push
supabase functions deploy
supabase status
```

### To be done:

crons required:
partioning audit log monthly
orphan node and edge cleanup
object storage cleanup
rls extra removals: merge multiple rls policies for less cpu usage
