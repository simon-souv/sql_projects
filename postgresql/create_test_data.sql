-- ================================================================
-- Connect to mydb first:
-- psql -U simon -h 127.0.0.1 -p 5432 -d mydb
-- ================================================================

-- ----------------------------------------------------------------
-- 1. Create the schema if it doesn't exist
-- ----------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS work_schema;

-- ----------------------------------------------------------------
-- 2. Set simon's search_path permanently (idempotent by nature)
-- ----------------------------------------------------------------
ALTER ROLE simon SET search_path TO work_schema, public;

-- Apply to current session as well
SET search_path TO work_schema, public;

-- ----------------------------------------------------------------
-- 3. Create table_a if it doesn't exist
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS work_schema.table_a (
    identite VARCHAR(100) NOT NULL
);

-- ----------------------------------------------------------------
-- 4. Create table_b if it doesn't exist
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS work_schema.table_b (
    age INTEGER NOT NULL
);

-- ----------------------------------------------------------------
-- 5. Create indexes if they don't exist
-- ----------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'work_schema'
          AND tablename  = 'table_a'
          AND indexname  = 'idx_table_a_identite'
    ) THEN
        CREATE INDEX idx_table_a_identite ON work_schema.table_a(identite);
        RAISE NOTICE 'Index idx_table_a_identite created.';
    ELSE
        RAISE NOTICE 'Index idx_table_a_identite already exists, skipping.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'work_schema'
          AND tablename  = 'table_b'
          AND indexname  = 'idx_table_b_age'
    ) THEN
        CREATE INDEX idx_table_b_age ON work_schema.table_b(age);
        RAISE NOTICE 'Index idx_table_b_age created.';
    ELSE
        RAISE NOTICE 'Index idx_table_b_age already exists, skipping.';
    END IF;
END;
$$;

-- ----------------------------------------------------------------
-- 6. Insert test data only if tables are empty
-- ----------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM work_schema.table_a LIMIT 1) THEN
        INSERT INTO work_schema.table_a (identite) VALUES
            ('Alice'),
            ('Bob'),
            ('Charlie'),
            ('Diana');
        RAISE NOTICE 'Test data inserted into table_a.';
    ELSE
        RAISE NOTICE 'Table table_a already has data, skipping insert.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM work_schema.table_b LIMIT 1) THEN
        INSERT INTO work_schema.table_b (age) VALUES
            (25),
            (34),
            (47),
            (52);
        RAISE NOTICE 'Test data inserted into table_b.';
    ELSE
        RAISE NOTICE 'Table table_b already has data, skipping insert.';
    END IF;
END;
$$;

-- ----------------------------------------------------------------
-- 7. Create or replace the function (always safe to re-run)
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION work_schema.get_identite_minmax(
    OUT min_identite VARCHAR,
    OUT max_identite VARCHAR
)
RETURNS RECORD
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT MIN(identite), MAX(identite)
    INTO   min_identite, max_identite
    FROM   work_schema.table_a;
END;
$$;

-- ----------------------------------------------------------------
-- 8. Verify everything
-- ----------------------------------------------------------------
SELECT schemaname, tablename
FROM   pg_tables
WHERE  schemaname = 'work_schema';

SELECT schemaname, indexname
FROM   pg_indexes
WHERE  schemaname = 'work_schema';

SELECT routine_schema, routine_name
FROM   information_schema.routines
WHERE  routine_schema = 'work_schema';

SELECT * FROM work_schema.get_identite_minmax();