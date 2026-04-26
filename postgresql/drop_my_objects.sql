-- ================================================================
-- drop_my_objects.sql
-- Automatically resolves the target schema from the role's
-- configured default search_path — no hardcoding needed.
--
-- Connect as the target user, e.g.:
-- psql -U simon -h 127.0.0.1 -p 5432 -d mydb -f drop_my_objects.sql
-- psql -U chloe -h 127.0.0.1 -p 5432 -d mydb -f drop_my_objects.sql
-- ================================================================

-- ================================================================
-- 1. Create (or replace) the procedure
-- ================================================================
CREATE OR REPLACE PROCEDURE drop_my_objects(p_schema TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    r       RECORD;
    v_sql   TEXT;
BEGIN
    -- Safety guard: never operate on public
    IF lower(p_schema) = 'public' THEN
        RAISE EXCEPTION 'Resolved schema is public. Aborting for safety.';
    END IF;

    -- Verify the schema actually exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.schemata
        WHERE schema_name = p_schema
    ) THEN
        RAISE EXCEPTION 'Schema "%" does not exist. Aborting.', p_schema;
    END IF;

    RAISE NOTICE 'Target schema: %', p_schema;

    -- ----------------------------------------------------------------
    -- 2. Drop TRIGGERS
    -- ----------------------------------------------------------------
    FOR r IN
        SELECT DISTINCT trigger_name, event_object_table
        FROM   information_schema.triggers
        WHERE  trigger_schema = p_schema
    LOOP
        v_sql := format('DROP TRIGGER IF EXISTS %I ON %I.%I CASCADE',
                        r.trigger_name, p_schema, r.event_object_table);
        RAISE NOTICE '%', v_sql;
        EXECUTE v_sql;
    END LOOP;

    -- ----------------------------------------------------------------
    -- 3. Drop VIEWS and MATERIALIZED VIEWS
    -- ----------------------------------------------------------------
    FOR r IN
        SELECT table_name
        FROM   information_schema.views
        WHERE  table_schema = p_schema
    LOOP
        v_sql := format('DROP VIEW IF EXISTS %I.%I CASCADE', p_schema, r.table_name);
        RAISE NOTICE '%', v_sql;
        EXECUTE v_sql;
    END LOOP;

    FOR r IN
        SELECT matviewname
        FROM   pg_matviews
        WHERE  schemaname = p_schema
    LOOP
        v_sql := format('DROP MATERIALIZED VIEW IF EXISTS %I.%I CASCADE', p_schema, r.matviewname);
        RAISE NOTICE '%', v_sql;
        EXECUTE v_sql;
    END LOOP;

    -- ----------------------------------------------------------------
    -- 4. Drop TABLES
    -- ----------------------------------------------------------------
    FOR r IN
        SELECT table_name
        FROM   information_schema.tables
        WHERE  table_schema = p_schema
          AND  table_type   = 'BASE TABLE'
    LOOP
        v_sql := format('DROP TABLE IF EXISTS %I.%I CASCADE', p_schema, r.table_name);
        RAISE NOTICE '%', v_sql;
        EXECUTE v_sql;
    END LOOP;

    -- ----------------------------------------------------------------
    -- 5. Drop SEQUENCES
    -- ----------------------------------------------------------------
    FOR r IN
        SELECT sequence_name
        FROM   information_schema.sequences
        WHERE  sequence_schema = p_schema
    LOOP
        v_sql := format('DROP SEQUENCE IF EXISTS %I.%I CASCADE', p_schema, r.sequence_name);
        RAISE NOTICE '%', v_sql;
        EXECUTE v_sql;
    END LOOP;

    -- ----------------------------------------------------------------
    -- 6. Drop ROUTINES (functions + procedures), excluding this one
    -- ----------------------------------------------------------------
    FOR r IN
        SELECT  p.proname                                      AS routine_name,
                pg_get_function_identity_arguments(p.oid)     AS args,
                CASE p.prokind
                    WHEN 'f' THEN 'FUNCTION'
                    WHEN 'p' THEN 'PROCEDURE'
                    WHEN 'a' THEN 'AGGREGATE'
                    WHEN 'w' THEN 'FUNCTION'
                END                                            AS kind
        FROM    pg_proc        p
        JOIN    pg_namespace   n ON n.oid = p.pronamespace
        WHERE   n.nspname = p_schema
          AND   p.proname <> 'drop_my_objects'
    LOOP
        v_sql := format('DROP %s IF EXISTS %I.%I(%s) CASCADE',
                        r.kind, p_schema, r.routine_name, r.args);
        RAISE NOTICE '%', v_sql;
        EXECUTE v_sql;
    END LOOP;

    -- ----------------------------------------------------------------
    -- 7. Drop TYPES (composite, enum, domain, range)
    -- ----------------------------------------------------------------
    FOR r IN
        SELECT  t.typname,
                CASE t.typtype
                    WHEN 'c' THEN 'TYPE'
                    WHEN 'e' THEN 'TYPE'
                    WHEN 'd' THEN 'DOMAIN'
                    WHEN 'r' THEN 'TYPE'
                    WHEN 'm' THEN 'TYPE'
                END AS kind
        FROM    pg_type      t
        JOIN    pg_namespace n ON n.oid = t.typnamespace
        WHERE   n.nspname  = p_schema
          AND   t.typtype  IN ('c','e','d','r','m')
          AND   NOT EXISTS (
                    SELECT 1 FROM pg_class c
                    WHERE  c.reltype = t.oid
                      AND  c.relkind IN ('r','v','m')
                )
    LOOP
        v_sql := format('DROP %s IF EXISTS %I.%I CASCADE', r.kind, p_schema, r.typname);
        RAISE NOTICE '%', v_sql;
        EXECUTE v_sql;
    END LOOP;

    -- ----------------------------------------------------------------
    -- 8. Final summary
    -- ----------------------------------------------------------------
    RAISE NOTICE '=== Remaining objects in schema % ===', p_schema;
    FOR r IN
        SELECT  c.relkind, count(*) AS cnt
        FROM    pg_class     c
        JOIN    pg_namespace n ON n.oid = c.relnamespace
        WHERE   n.nspname = p_schema
        GROUP BY c.relkind
    LOOP
        RAISE NOTICE 'relkind=% : % object(s)', r.relkind, r.cnt;
    END LOOP;

END;
$$;

-- ================================================================
-- 2. Resolve the schema from the role's persistent search_path
--    and call the procedure — fully automatic, no hardcoding
-- ================================================================
DO $$
DECLARE
    v_raw_path  TEXT;
    v_schema    TEXT;
BEGIN
    -- Read the persistent search_path from pg_roles and extract
    -- the value in a single statement
    SELECT replace(cfg, 'search_path=', '')
    INTO   v_raw_path
    FROM   pg_roles, unnest(rolconfig) AS cfg
    WHERE  rolname = current_user
      AND  cfg LIKE 'search_path=%';

    IF v_raw_path IS NULL THEN
        RAISE EXCEPTION 'No persistent search_path configured for role "%". '
                        'Run: ALTER ROLE % SET search_path TO your_schema, public;',
                        current_user, current_user;
    END IF;

    RAISE NOTICE 'Raw search_path for role %: %', current_user, v_raw_path;

    -- Pick the first non-public, non-$user entry
    SELECT trim(part)
    INTO   v_schema
    FROM   unnest(string_to_array(v_raw_path, ',')) AS part
    WHERE  trim(part) NOT IN ('public', '"$user"', '$user')
      AND  trim(part) <> ''
    LIMIT 1;

    IF v_schema IS NULL THEN
        RAISE EXCEPTION 'No valid non-public schema found in search_path "%". Aborting.', v_raw_path;
    END IF;

    RAISE NOTICE 'Resolved target schema: %', v_schema;

    CALL drop_my_objects(v_schema);

    -- Normal path cleanup
    DROP PROCEDURE IF EXISTS drop_my_objects(TEXT);
    RAISE NOTICE 'Procedure drop_my_objects dropped.';

EXCEPTION
    WHEN OTHERS THEN
        -- Exception path cleanup — runs on any error
        DROP PROCEDURE IF EXISTS drop_my_objects(TEXT);
        RAISE NOTICE 'Procedure drop_my_objects dropped after error.';
        -- Re-raise the original error so it is still visible
        RAISE;
END;
$$;