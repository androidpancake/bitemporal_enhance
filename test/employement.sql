SELECT bitemporal_internal.ll_bitemporal_coalesce(
    'test_1',
    'employement',
    'employee_id',
    '1',
    ARRAY['name', 'department', 'salary', 'role']
);

SELECT bitemporal_internal.ll_bitemporal_insert(
    'test_1.employement',
    'employee_id, name, department, salary, role',
    '2, ''Danny'', ''IT'', 75000, ''Junior''',
    temporal_relationships.timeperiod('2024-01-01', '2024-06-30'),
    temporal_relationships.timeperiod(now(), 'infinity')
);

SELECT bitemporal_internal.ll_bitemporal_insert(
    'test_1.employement',
    'employee_id, name, department, salary, role',
    '2, ''Danny'', ''IT'', 75000, ''Junior''',
    temporal_relationships.timeperiod('2024-06-30', '2024-10-30'),
    temporal_relationships.timeperiod(now(), 'infinity')
);

create sequence test_1.emp_id_seq;

SELECT * FROM bitemporal_internal.ll_bitemporal_insert('test_1.employement'
,$$employee_id, name, department, salary, role$$
,quote_literal(nextval('test_1.emp_id_seq'))||$$,
'Danny', 'Finance', '75000', 'Junior'$$
,temporal_relationships.timeperiod('2024-08-30', 'infinity') --effective
,temporal_relationships.timeperiod(now(), 'infinity') --asserted
);

SELECT employee_id, name, department, salary, role, effective, asserted 
FROM test_1.employement 
WHERE now() <@ asserted
ORDER BY employee_id, effective;

SELECT * FROM bitemporal_internal.ll_temporal_count('test_1', 'employement');

SELECT bitemporal_internal.ll_bitemporal_coalesce(
    'test_1',
    'employement',
    'employee_id',
    '2',
    ARRAY['name', 'department', 'salary', 'role']
);

SELECT bitemporal_internal.ll_bitemporal_correction(
    'test_1',
    'employement',
    'salary',
    '84000',
    'employee_id',
    '1',
    temporal_relationships.timeperiod('2024-06-30'::timestamptz, '2024-10-30'::timestamptz)
);

SELECT bitemporal_internal.ll_generate_enhanced_insert_trigger(
    'test_1',
    'employement',
    'employee_id',
    ARRAY['name', 'department', 'salary', 'role']
);

SELECT bitemporal_internal.ll_bitemporal_inactivate(
    'test_1',
    'employement',
    'employee_id',
    '2',
    temporal_relationships.timeperiod('2024-06-30', '2024-10-30'),
    temporal_relationships.timeperiod(now(), 'infinity')
);

SELECT 
    count(*) as total_records,
    count(*) FILTER (WHERE now() <@ asserted) as active_records,
    count(*) FILTER (WHERE now() >@ asserted) as historical_records
FROM test_1.employement;

SELECT bitemporal_internal.ll_bitemporal_delete(
    'test_1.employement',
    'employee_id',
    '2',
    temporal_relationships.timeperiod(now(), 'infinity')
);






