# SupaMax

A hierarchical, permission-based access control system and CRM built on Supabase. SupaMax implements a Directed Acyclic Graph (DAG) structure for organizational management with granular role-based permissions and a complete CRM suite.

## Architecture Overview

### Core Concepts

- **DAG Structure**: Uses a closure table pattern (`closure_dominance`) for efficient tree traversal and dominance queries
- **Node Types**:
  - `user` - Authenticated users with Supabase Auth linkage
  - `group` - Organizational containers (companies, teams, departments)
  - `role` - Permission carriers with 256-bit permission bitmaps
- **Permission System**: 256-bit bitmap allowing for fine-grained capability control
- **Dominance Model**: Parent nodes control child nodes; permissions flow downward through roles

## Database Schema

### Core Graph Tables

| Table                 | Purpose                                                        |
| --------------------- | -------------------------------------------------------------- |
| `dag_node`            | Stores users, groups, and roles with type-specific constraints |
| `dag_edge`            | Parent-child relationships forming the DAG                     |
| `closure_dominance`   | Transitive closure for O(1) dominance checks                   |
| `permission_manifest` | Maps permission slugs to bit indices (0-255)                   |

### CRM Module Tables

| Table                  | Purpose                                       |
| ---------------------- | --------------------------------------------- |
| `crm_label`            | Configurable labels/statuses for CRM entities |
| `account`              | Company/organization records                  |
| `contact`              | People associated with accounts               |
| `opportunity`          | Sales opportunities linked to accounts        |
| `project`              | Projects derived from opportunities           |
| `opportunity_activity` | Audit log for opportunity changes             |

## Security Model

### Row Level Security (RLS)

All tables use RLS policies based on:

1. **Permission checks** - User must have specific capability bit set
2. **Dominance checks** - User must dominate (be ancestor of) the resource owner
3. **Membership checks** - User must belong to the same group/role hierarchy

### Key Security Functions

- `get_graph_context()` - Returns current user's node ID, effective permissions, and memberships
- `assert_dominance()` - Validates actor controls target node
- `assert_permission()` - Validates actor has specific permission
- `assert_no_escalation()` - Prevents privilege escalation when assigning permissions

## API Functions

### Graph Management

| Function                                        | Permission Required          | Description                          |
| ----------------------------------------------- | ---------------------------- | ------------------------------------ |
| `rpc_create_group(parent_id, label)`            | `NODE_CREATE`                | Create new group under parent        |
| `rpc_create_role(parent_id, label, bits)`       | `NODE_CREATE`, `ROLE_MANAGE` | Create role with permission set      |
| `rpc_link_node(parent, child)`                  | `EDGE_LINK`                  | Create edge between existing nodes   |
| `rpc_unlink_node(parent, child)`                | `EDGE_UNLINK`                | Remove edge (prevents orphans)       |
| `rpc_delete_node(target_id)`                    | `NODE_DELETE`                | Delete leaf node only                |
| `rpc_invite_user(parent_id, label, expires_in)` | `NODE_CREATE`                | Generate invite token for new user   |
| `rpc_claim_invite(token)`                       | -                            | Convert invite to authenticated user |

### Context Helpers

- `current_node_id()` - Get UUID of current auth user in graph
- `get_client_context()` - JSON context for frontend consumption
- `get_perm_id(slug)` - Resolve permission slug to bit index

## Permission Reference

### Graph Structure (0-10)

| Bit | Slug          | Description           |
| --- | ------------- | --------------------- |
| 0   | `GRAPH_READ`  | View graph structure  |
| 1   | `NODE_CREATE` | Create nodes          |
| 2   | `NODE_DELETE` | Delete leaf nodes     |
| 3   | `EDGE_LINK`   | Link nodes            |
| 4   | `EDGE_UNLINK` | Unlink nodes          |
| 10  | `ROLE_MANAGE` | Edit role permissions |

### CRM Configuration (31-33)

| Bit | Slug               | Description   |
| --- | ------------------ | ------------- |
| 31  | `CRM_LABEL_INSERT` | Create labels |
| 32  | `CRM_LABEL_UPDATE` | Update labels |
| 33  | `CRM_LABEL_DELETE` | Delete labels |

### Account (40-43)

| Bit | Slug             | Description     |
| --- | ---------------- | --------------- |
| 40  | `ACCOUNT_SELECT` | View accounts   |
| 41  | `ACCOUNT_INSERT` | Create accounts |
| 42  | `ACCOUNT_UPDATE` | Edit accounts   |
| 43  | `ACCOUNT_DELETE` | Delete accounts |

### Contact (50-53)

| Bit | Slug             | Description     |
| --- | ---------------- | --------------- |
| 50  | `CONTACT_SELECT` | View contacts   |
| 51  | `CONTACT_INSERT` | Create contacts |
| 52  | `CONTACT_UPDATE` | Edit contacts   |
| 53  | `CONTACT_DELETE` | Delete contacts |

### Opportunity (60-66)

| Bit | Slug                  | Description          |
| --- | --------------------- | -------------------- |
| 60  | `OPP_SELECT`          | View opportunities   |
| 61  | `OPP_INSERT`          | Create opportunities |
| 62  | `OPP_UPDATE`          | Edit opportunities   |
| 63  | `OPP_DELETE`          | Delete opportunities |
| 64  | `OPP_ACTIVITY_INSERT` | Log activities       |
| 65  | `OPP_ACTIVITY_UPDATE` | Edit activities      |
| 66  | `OPP_ACTIVITY_DELETE` | Delete activities    |

### Project (70-73)

| Bit | Slug          | Description     |
| --- | ------------- | --------------- |
| 70  | `PROJ_SELECT` | View projects   |
| 71  | `PROJ_INSERT` | Create projects |
| 72  | `PROJ_UPDATE` | Edit projects   |
| 73  | `PROJ_DELETE` | Delete projects |

## Deployment

### Prerequisites

- Supabase CLI installed
- PostgreSQL 14+ (for local development)
- Node.js environment (for edge functions if applicable)

### Deploy

```bash
# Login to Supabase
supabase login

# Link to your project
supabase link --project-ref &lt;your-project-ref&gt;

# Push migrations to database
supabase db push --password &lt;your-db-password&gt;
```
