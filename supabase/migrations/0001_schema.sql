-- 1. Enum Types
DO $$
BEGIN
    IF NOT EXISTS(
        SELECT
            1
        FROM
            pg_type
        WHERE
            typname = 'node_type') THEN
    CREATE TYPE node_type AS ENUM(
        'user',
        'group',
        'role'
);
END IF;
END
$$;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Tables
CREATE TABLE IF NOT EXISTS dag_node(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    type node_type NOT NULL,
    label text NOT NULL,
    -- User State
    auth_user_id uuid UNIQUE,
    invite_hash text,
    invite_expires timestamptz,
    -- Role State
    permission_bits bit(256),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    -- Constraints ensuring Type Safety
    CONSTRAINT chk_user_valid CHECK (type <> 'user' OR ((auth_user_id IS NOT NULL AND invite_hash IS NULL) OR (auth_user_id IS NULL AND invite_hash IS NOT NULL))),
    CONSTRAINT chk_group_valid CHECK (type <> 'group' OR (auth_user_id IS NULL AND invite_hash IS NULL AND permission_bits IS NULL)),
    CONSTRAINT chk_role_valid CHECK (type <> 'role' OR (permission_bits IS NOT NULL AND auth_user_id IS NULL))
);

CREATE TABLE IF NOT EXISTS dag_edge(
    parent_id uuid NOT NULL REFERENCES dag_node(id) ON DELETE CASCADE,
    child_id uuid NOT NULL REFERENCES dag_node(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (parent_id, child_id),
    CONSTRAINT chk_no_self_loops CHECK (parent_id <> child_id)
);

CREATE TABLE IF NOT EXISTS closure_dominance(
    ancestor_id uuid NOT NULL REFERENCES dag_node(id) ON DELETE CASCADE,
    descendant_id uuid NOT NULL REFERENCES dag_node(id) ON DELETE CASCADE,
    depth integer NOT NULL DEFAULT 0,
    PRIMARY KEY (ancestor_id, descendant_id)
);

CREATE TABLE IF NOT EXISTS permission_manifest(
    bit_index int PRIMARY KEY CHECK (bit_index BETWEEN 0 AND 255),
    slug text NOT NULL UNIQUE,
    description text
);

-- 3. Indexes (Performance Optimization)
CREATE INDEX idx_edge_parent ON dag_edge(parent_id);

CREATE INDEX idx_edge_child ON dag_edge(child_id);

CREATE INDEX idx_closure_anc ON closure_dominance(ancestor_id);

CREATE INDEX idx_closure_desc ON closure_dominance(descendant_id);

CREATE INDEX idx_node_auth ON dag_node(auth_user_id);

CREATE UNIQUE INDEX idx_node_invite ON dag_node(invite_hash)
WHERE
    invite_hash IS NOT NULL;

CREATE INDEX idx_node_role_bits ON dag_node(id) INCLUDE (permission_bits)
WHERE
    type = 'role';

-- 4. Initial Security Lockdown
ALTER TABLE dag_node ENABLE ROW LEVEL SECURITY;

ALTER TABLE dag_edge ENABLE ROW LEVEL SECURITY;

ALTER TABLE closure_dominance ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON dag_node, dag_edge, closure_dominance FROM public, anon, authenticated;

-- We grant SELECT only via specific policies later
