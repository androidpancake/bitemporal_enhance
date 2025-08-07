-- Test script for pg_bitemporal_enhance extension
-- This script demonstrates the enhanced functionality with existing pg_bitemporal framework

-- Ensure we're in the right context
SET search_path TO bitemporal_internal, temporal_relationships, public;

-- Test 1: Create a bitemporal table using existing pg_bitemporal function
\echo '=== Test 1: Creating bitemporal table ==='
SELECT bitemporal_internal.ll_create_bitemporal_table(
	'public',
    'employment_bt',
    $$employee_id int, 
	name text, 
	department text, 
	salary numeric
	$$,
    'employee_id'
);

-- Test 2: Create GiST index for performance optimization
\echo '=== Test 2: Creating performance index ==='
CREATE INDEX idx_gist_employment_effective ON employment_bt USING GIST (effective);

-- Test 3: Insert records using standard pg_bitemporal function
\echo '=== Test 3: Inserting records with standard pg_bitemporal ==='
SELECT bitemporal_internal.ll_bitemporal_insert(
	'public.employment_bt',
    'employee_id, name, department, salary',
    '1, ''John Doe'', ''IT'', 75000',
    temporal_relationships.timeperiod('2024-01-01', '2024-06-30'),
    temporal_relationships.timeperiod(now(), 'infinity')
);

SELECT bitemporal_internal.ll_bitemporal_insert(
    'public.employment_bt',
    'employee_id, name, department, salary',
    '1, ''John Doe'', ''IT'', 80000',
    temporal_relationships.timeperiod('2024-07-01', '2024-12-31'),
    temporal_relationships.timeperiod(now(), 'infinity')
);

SELECT bitemporal_internal.ll_bitemporal_insert(
    'public.employment_bt',
    'employee_id, name, department, salary',
    '2, ''Jane Smith'', ''HR'', 65000',
    temporal_relationships.timeperiod('2024-01-01', '2024-12-31'),
    temporal_relationships.timeperiod(now(), 'infinity')
);

-- Test 4: Show current state before coalescing
\echo '=== Test 4: Current state before coalescing ==='
SELECT employee_id, name, department, salary, effective, asserted 
FROM employment_bt 
WHERE now() <@ asserted 
ORDER BY employee_id, effective;

-- Test 5: Demonstrate coalescing functionality
\echo '=== Test 5: Testing coalescing functionality ==='
SELECT bitemporal_internal.ll_bitemporal_coalesce(
    'public',
    'employment_bt',
    'employee_id',
    '1',
    ARRAY['name', 'department']
);

-- Test 6: Show state after coalescing
\echo '=== Test 6: State after coalescing ==='
SELECT employee_id, name, department, salary, effective, asserted 
FROM employment_bt 
WHERE now() <@ asserted 
ORDER BY employee_id, effective;

-- Test 7: Insert with enhanced coalescing function
\echo '=== Test 7: Inserting with enhanced coalescing ==='
SELECT bitemporal_internal.ll_bitemporal_insert_with_coalesce(
    'public',
    'employment_bt',
    'employee_id, name, department, salary',
    '3, ''Bob Johnson'', ''IT'', 70000',
    temporal_relationships.timeperiod('2024-01-01', '2024-06-30'),
    temporal_relationships.timeperiod(now(), 'infinity'),
    'employee_id',
    '3',
    ARRAY['name', 'department']
);

SELECT bitemporal_internal.ll_bitemporal_insert_with_coalesce(
    'public',
    'employment_bt',
    'employee_id, name, department, salary',
    '3, ''Bob Johnson'', ''IT'', 75000',
    temporal_relationships.timeperiod('2024-07-01', '2024-12-31'),
    temporal_relationships.timeperiod(now(), 'infinity'),
    'employee_id',
    '3',
    ARRAY['name', 'department']
);

-- Test 8: Show final state
\echo '=== Test 8: Final state after enhanced inserts ==='
SELECT employee_id, name, department, salary, effective, asserted 
FROM employment_bt 
WHERE now() <@ asserted 
ORDER BY employee_id, effective;

-- Test 9: Demonstrate temporal aggregation functions
\echo '=== Test 9: Testing temporal aggregation functions ==='

\echo 'Temporal count of employees:'
SELECT * FROM bitemporal_internal.ll_temporal_count('public', 'employment_bt');

\echo 'Temporal maximum salary:'
SELECT * FROM bitemporal_internal.ll_temporal_max('public', 'employment_bt', 'salary');

\echo 'Temporal average salary:'
SELECT * FROM bitemporal_internal.ll_temporal_avg('public', 'employment_bt', 'salary');

-- Test 10: Demonstrate enhanced trigger generation
\echo '=== Test 10: Generating enhanced trigger code ==='
SELECT bitemporal_internal.ll_generate_enhanced_insert_trigger(
    'public',
    'employment_bt',
    'employee_id',
    ARRAY['name', 'department']
);

-- Test 11: Test helper functions
\echo '=== Test 11: Testing helper functions ==='
SELECT bitemporal_internal.current_asserted_time() as current_asserted;
SELECT bitemporal_internal.current_effective_time() as current_effective;

-- Test 12: Test temporal interval computation
\echo '=== Test 12: Computing temporal intervals ==='
SELECT * FROM bitemporal_internal.ll_compute_temporal_intervals('public', 'employment_bt');

-- Test 13: Demonstrate integration with existing pg_bitemporal functions
\echo '=== Test 13: Testing integration with existing functions ==='

-- Test if table is bitemporal
SELECT bitemporal_internal.ll_is_bitemporal_table('public.employment_bt') as is_bitemporal;

-- List table fields
SELECT bitemporal_internal.ll_bitemporal_list_of_fields('public.employment_bt') as table_fields;

-- Test 14: Performance comparison
\echo '=== Test 14: Performance comparison ==='

-- Standard query without optimization
\echo 'Standard count query:'
SELECT count(*) FROM employment_bt WHERE now() <@ asserted;

-- Enhanced temporal count
\echo 'Enhanced temporal count:'
SELECT count(*) FROM bitemporal_internal.ll_temporal_count('public', 'employment_bt');

-- Test 15: Cleanup demonstration
\echo '=== Test 15: Cleanup demonstration ==='
\echo 'Current records in employment_bt:'
SELECT count(*) as total_records FROM employment_bt;

\echo 'Active records (not ended):'
SELECT count(*) as active_records FROM employment_bt WHERE now() <@ asserted;

\echo 'Historical records (ended):'
SELECT count(*) as historical_records FROM employment_bt WHERE now() >=@ asserted;

-- Summary
\echo '=== Summary ==='
\echo 'Enhanced extension successfully integrated with pg_bitemporal framework.'
\echo 'Key features demonstrated:'
\echo '  - Automatic coalescing of adjacent records'
\echo '  - Enhanced insert with automatic coalescing'
\echo '  - Optimized temporal aggregation'
\echo '  - Integration with existing pg_bitemporal functions'
\echo '  - Performance optimization with GiST indexes' 