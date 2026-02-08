-- 1. Boolean Predicate: Do I dominate target?
CREATE OR REPLACE FUNCTION predicate_dominates(p_actor uuid, p_target uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public
    AS $$
    SELECT
        EXISTS(
            SELECT
                1
            FROM
                closure_dominance
            WHERE
                ancestor_id = p_actor
                AND descendant_id = p_target);
$$;

-- 2. Boolean Predicate: Do I have this permission bit?
CREATE OR REPLACE FUNCTION predicate_has_perm(p_ctx graph_context, p_perm_slug text)
    RETURNS boolean
    LANGUAGE sql
    IMMUTABLE
    SET search_path = public
    AS $$
    SELECT
        get_bit(p_ctx.perms, get_perm_id(p_perm_slug)) = 1;
$$;

-- 3. Assertion: Ensure Actor Exists
CREATE OR REPLACE FUNCTION assert_authenticated()
    RETURNS graph_context
    LANGUAGE plpgsql
    STABLE
    SET search_path = public
    AS $$
DECLARE
    ctx graph_context;
BEGIN
    ctx := get_graph_context();
    IF ctx.node_id IS NULL THEN
        RAISE EXCEPTION 'ERR_NO_NODE: User is not linked to the graph';
    END IF;
    RETURN ctx;
END;
$$;

-- 4. Assertion: Ensure Dominance (Access Control)
CREATE OR REPLACE FUNCTION assert_dominance(p_ctx graph_context, p_target_id uuid)
    RETURNS void
    LANGUAGE plpgsql
    STABLE
    SET search_path = public
    AS $$
BEGIN
    IF NOT predicate_dominates(p_ctx.node_id, p_target_id) THEN
        RAISE EXCEPTION 'ERR_ACCESS_DENIED: You do not control this node';
    END IF;
END;
$$;

-- 5. Assertion: Ensure Permission (Capability Control)
CREATE OR REPLACE FUNCTION assert_permission(p_ctx graph_context, p_slug text)
    RETURNS void
    LANGUAGE plpgsql
    STABLE
    SET search_path = public
    AS $$
BEGIN
    IF NOT predicate_has_perm(p_ctx, p_slug) THEN
        RAISE EXCEPTION 'ERR_PERM_DENIED: Missing permission %', p_slug;
    END IF;
END;
$$;

-- 6. Assertion: Anti-Escalation (Cannot assign bits I don't have)
CREATE OR REPLACE FUNCTION assert_no_escalation(p_ctx graph_context, p_bits bit(256))
    RETURNS void
    LANGUAGE plpgsql
    STABLE
    SET search_path = public
    AS $$
BEGIN
    IF(p_bits & ~ p_ctx.perms) <> B'0'::bit(256) THEN
        RAISE EXCEPTION 'ERR_ESCALATION: You cannot assign permissions you do not possess';
    END IF;
END;
$$;

