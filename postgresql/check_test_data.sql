-- ================================================================
-- Connect to mydb first:
-- psql -U simon -h 127.0.0.1 -p 5432 -d mydb
-- ================================================================

SELECT schemaname, tablename
FROM   pg_tables
WHERE  schemaname = 'work_schema';

SELECT schemaname, indexname
FROM   pg_indexes
WHERE  schemaname = 'work_schema';

SELECT routine_schema, routine_name
FROM   information_schema.routines
WHERE  routine_schema = 'work_schema';

