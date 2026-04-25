set pages 0
set lines 300
set heading off
set feedback off

spool /tmp/drop_my_objects.sql

-- Disable all constraints first (to avoid FK dependency issues)
select 'alter table '||table_name||' disable constraint '||constraint_name||';'
from user_constraints
where constraint_type = 'R';

-- Drop tables (cascade handles remaining constraints)
select 'drop table '||table_name||' cascade constraints purge;'
from user_tables;

-- Drop all other object types
select 'drop '||object_type||' '||object_name||';'
from user_objects
where object_type in (
    'VIEW',
    'SEQUENCE',
    'PROCEDURE',
    'FUNCTION',
    'PACKAGE',
    'PACKAGE BODY',
    'TRIGGER',
    'SYNONYM',
    'TYPE',
    'TYPE BODY',
    'MATERIALIZED VIEW',
    'DATABASE LINK'
)
and generated = 'N'            -- exclude system-generated objects
order by
    -- drop bodies before specs
    case object_type
        when 'PACKAGE BODY' then 1
        when 'TYPE BODY'    then 2
        when 'TRIGGER'      then 3
        when 'VIEW'         then 4
        when 'MATERIALIZED VIEW' then 5
        when 'SYNONYM'      then 6
        when 'DATABASE LINK' then 7
        when 'PROCEDURE'    then 8
        when 'FUNCTION'     then 9
        when 'PACKAGE'      then 10
        when 'TYPE'         then 11
        when 'SEQUENCE'     then 12
        else 99
    end;

spool off

@/tmp/drop_my_objects.sql

PROMPT
PROMPT === Remaining objects (should be empty) ===
select object_type, count(*) from user_objects group by object_type order by object_type;

exit