# Migration Guide: pg_bitemporal_enhance

This guide helps you migrate from the original enhancement to the adapted version that integrates with the existing pg_bitemporal framework.

## Overview of Changes

The enhanced extension has been adapted to work seamlessly with the existing pg_bitemporal framework. Key changes include:

### 1. Schema and Naming Conventions

| Original | Adapted |
|----------|---------|
| `current_transaction_time()` | `bitemporal_internal.current_asserted_time()` |
| `tsrange` | `temporal_relationships.timeperiod` |
| `validity` column | `effective` column |
| `transaction_time` column | `asserted` column |
| `bitemporal_coalesce()` | `bitemporal_internal.ll_bitemporal_coalesce()` |

### 2. Function Signatures

| Original | Adapted |
|----------|---------|
| `bitemporal_coalesce(target_table, pk_column, pk_value, value_columns)` | `ll_bitemporal_coalesce(schema_name, table_name, business_key, business_value, value_columns)` |
| `temporal_count(target_table)` | `ll_temporal_count(schema_name, table_name)` |
| `temporal_max_salary(target_table)` | `ll_temporal_max(schema_name, table_name, column_name)` |

## Migration Steps

### Step 1: Install the Enhanced Extension

```sql
-- Install the enhanced extension
CREATE EXTENSION pg_bitemporal_enhance;
```

### Step 2: Update Function Calls

#### Before (Original Enhancement):
```sql
-- Coalescing
SELECT bitemporal_coalesce(
    'employment'::regclass,
    'id',
    '1',
    ARRAY['name', 'department']
);

-- Temporal aggregation
SELECT * FROM temporal_count('employment'::regclass);
SELECT * FROM temporal_max_salary('employment'::regclass);
```

#### After (Adapted Enhancement):
```sql
-- Coalescing
SELECT bitemporal_internal.ll_bitemporal_coalesce(
    'public',
    'employment_bt',
    'employee_id',
    '1',
    ARRAY['name', 'department']
);

-- Temporal aggregation
SELECT * FROM bitemporal_internal.ll_temporal_count('public', 'employment_bt');
SELECT * FROM bitemporal_internal.ll_temporal_max('public', 'employment_bt', 'salary');
```

### Step 3: Update Table References

#### Before:
```sql
-- Using regclass references
SELECT * FROM temporal_count('employment'::regclass);
```

#### After:
```sql
-- Using schema and table name
SELECT * FROM bitemporal_internal.ll_temporal_count('public', 'employment_bt');
```

### Step 4: Update Time Period References

#### Before:
```sql
-- Using tsrange
SELECT * FROM table WHERE validity && tsrange('2024-01-01', '2024-12-31');
```

#### After:
```sql
-- Using timeperiod domain
SELECT * FROM table WHERE effective && temporal_relationships.timeperiod('2024-01-01', '2024-12-31');
```

### Step 5: Update Insert Operations

#### Before:
```sql
-- Original enhancement insert
SELECT bitemporal_insert_with_coalesce(
    'employment'::regclass,
    '{"name": "John", "department": "IT", "validity": "[2024-01-01,2024-12-31]"}'
);
```

#### After:
```sql
-- Enhanced insert with coalescing
SELECT bitemporal_internal.ll_bitemporal_insert_with_coalesce(
    'public',
    'employment_bt',
    'name, department, salary',
    '''John Doe'', ''IT'', 75000',
    temporal_relationships.timeperiod('2024-01-01', '2024-12-31'),
    temporal_relationships.timeperiod(now(), 'infinity'),
    'employee_id',
    '1',
    ARRAY['name', 'department']
);
```

## Compatibility Matrix

### Fully Compatible Features

| Feature | Original | Adapted | Status |
|---------|----------|---------|--------|
| Automatic coalescing | ✅ | ✅ | Compatible |
| Temporal aggregation | ✅ | ✅ | Compatible |
| Performance optimization | ✅ | ✅ | Compatible |
| Trigger generation | ✅ | ✅ | Compatible |

### Enhanced Features

| Feature | Original | Adapted | Enhancement |
|---------|----------|---------|-------------|
| Schema integration | ❌ | ✅ | Full pg_bitemporal integration |
| Type safety | Basic | ✅ | Strong typing with domains |
| Error handling | Basic | ✅ | Enhanced error handling |
| Performance | Good | ✅ | Optimized with GiST indexes |

## Code Migration Examples

### Example 1: Simple Coalescing

#### Original Code:
```sql
-- Original coalescing
CREATE OR REPLACE FUNCTION coalesce_employment()
RETURNS void AS $$
BEGIN
    PERFORM bitemporal_coalesce(
        'employment'::regclass,
        'id',
        '1',
        ARRAY['name', 'department']
    );
END;
$$ LANGUAGE plpgsql;
```

#### Migrated Code:
```sql
-- Migrated coalescing
CREATE OR REPLACE FUNCTION coalesce_employment()
RETURNS void AS $$
BEGIN
    PERFORM bitemporal_internal.ll_bitemporal_coalesce(
        'public',
        'employment_bt',
        'employee_id',
        '1',
        ARRAY['name', 'department']
    );
END;
$$ LANGUAGE plpgsql;
```

### Example 2: Temporal Aggregation

#### Original Code:
```sql
-- Original temporal aggregation
CREATE OR REPLACE FUNCTION get_employee_stats()
RETURNS TABLE(count bigint, max_salary numeric) AS $$
BEGIN
    RETURN QUERY
    SELECT t.count, s.max_salary
    FROM temporal_count('employment'::regclass) t
    CROSS JOIN temporal_max_salary('employment'::regclass) s;
END;
$$ LANGUAGE plpgsql;
```

#### Migrated Code:
```sql
-- Migrated temporal aggregation
CREATE OR REPLACE FUNCTION get_employee_stats()
RETURNS TABLE(count bigint, max_salary numeric) AS $$
BEGIN
    RETURN QUERY
    SELECT t.count, s.max_value
    FROM bitemporal_internal.ll_temporal_count('public', 'employment_bt') t
    CROSS JOIN bitemporal_internal.ll_temporal_max('public', 'employment_bt', 'salary') s;
END;
$$ LANGUAGE plpgsql;
```

### Example 3: Enhanced Insert with Coalescing

#### Original Code:
```sql
-- Original enhanced insert
CREATE OR REPLACE FUNCTION insert_employee(data jsonb)
RETURNS void AS $$
BEGIN
    PERFORM bitemporal_insert_with_coalesce(
        'employment'::regclass,
        data
    );
END;
$$ LANGUAGE plpgsql;
```

#### Migrated Code:
```sql
-- Migrated enhanced insert
CREATE OR REPLACE FUNCTION insert_employee(
    p_name text,
    p_department text,
    p_salary numeric,
    p_employee_id text,
    p_effective_start date,
    p_effective_end date
)
RETURNS void AS $$
BEGIN
    PERFORM bitemporal_internal.ll_bitemporal_insert_with_coalesce(
        'public',
        'employment_bt',
        'name, department, salary',
        format('%L, %L, %s', p_name, p_department, p_salary),
        temporal_relationships.timeperiod(p_effective_start, p_effective_end),
        temporal_relationships.timeperiod(now(), 'infinity'),
        'employee_id',
        p_employee_id,
        ARRAY['name', 'department']
    );
END;
$$ LANGUAGE plpgsql;
```

## Testing Migration

### Step 1: Create Test Environment
```sql
-- Create test database
CREATE DATABASE test_bitemporal_enhance;
\c test_bitemporal_enhance

-- Install pg_bitemporal
CREATE EXTENSION pg_bitemporal;

-- Install enhanced extension
CREATE EXTENSION pg_bitemporal_enhance;
```

### Step 2: Run Migration Tests
```sql
-- Run the test script
\i test_enhanced_extension.sql
```

### Step 3: Verify Functionality
```sql
-- Test basic functionality
SELECT bitemporal_internal.ll_is_bitemporal_table('public.employment_bt');

-- Test enhanced functions
SELECT * FROM bitemporal_internal.ll_temporal_count('public', 'employment_bt');
```

## Troubleshooting Migration

### Common Issues

1. **Schema Not Found**
   ```sql
   -- Error: schema "bitemporal_internal" does not exist
   -- Solution: Ensure pg_bitemporal is installed first
   CREATE EXTENSION pg_bitemporal;
   CREATE EXTENSION pg_bitemporal_enhance;
   ```

2. **Type Mismatch**
   ```sql
   -- Error: function temporal_relationships.timeperiod(unknown, unknown) does not exist
   -- Solution: Use proper type casting
   temporal_relationships.timeperiod('2024-01-01'::date, '2024-12-31'::date)
   ```

3. **Function Not Found**
   ```sql
   -- Error: function bitemporal_internal.ll_bitemporal_coalesce does not exist
   -- Solution: Check extension installation
   SELECT * FROM pg_extension WHERE extname = 'pg_bitemporal_enhance';
   ```

### Verification Commands

```sql
-- Check extension installation
SELECT extname, extversion FROM pg_extension WHERE extname LIKE '%bitemporal%';

-- Check available functions
SELECT proname, proschema 
FROM pg_proc 
WHERE proschema = 'bitemporal_internal' 
AND proname LIKE '%coalesce%';

-- Test basic functionality
SELECT bitemporal_internal.current_asserted_time();
SELECT bitemporal_internal.current_effective_time();
```

## Performance Considerations

### Before Migration
- Monitor performance of existing temporal queries
- Note current query execution times
- Identify bottlenecks

### After Migration
- Create GiST indexes on effective columns
- Monitor coalescing performance
- Compare temporal aggregation performance

### Performance Monitoring
```sql
-- Monitor coalescing performance
EXPLAIN ANALYZE SELECT bitemporal_internal.ll_bitemporal_coalesce(
    'public', 'employment_bt', 'employee_id', '1', ARRAY['name', 'department']
);

-- Monitor temporal aggregation performance
EXPLAIN ANALYZE SELECT * FROM bitemporal_internal.ll_temporal_count('public', 'employment_bt');
```

## Rollback Plan

If migration issues occur, you can rollback by:

1. **Uninstall Enhanced Extension**
   ```sql
   DROP EXTENSION pg_bitemporal_enhance;
   ```

2. **Restore Original Functions**
   - Keep original enhancement functions if needed
   - Use original function signatures

3. **Verify Functionality**
   ```sql
   -- Test that original functions still work
   SELECT * FROM temporal_count('employment'::regclass);
   ```

## Support

For migration support:

1. Check the test script: `test_enhanced_extension.sql`
2. Review the documentation: `README_ENHANCED.md`
3. Run verification commands listed in troubleshooting section
4. Monitor performance before and after migration 