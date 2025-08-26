SELECT bitemporal_internal.ll_create_bitemporal_table(
	'test_1',
    'mentorship',
    $$mentorship_id int,
    mentor_id int,
	mentee_name text, 
	department text,
    trainee text 
	$$,
    'mentorship_id'
);

SELECT bitemporal_internal.ll_bitemporal_insert_reference(
    'test_1',
    'mentorship',
    'mentorship_id, mentor_id, mentee_name, department, trainee',
    '1, 3, ''Chery'', ''IT'', ''Frank''',
    temporal_relationships.timeperiod('2024-10-01', '2024-12-31'),
    temporal_relationships.timeperiod(now(), 'infinity'),
    'mentorship_id',
    '1',
    ARRAY['mentee_name', 'department', 'trainee']::text[],
    'employement',
    'employee_id',
    '3',
    'effective'
);

SELECT bitemporal_internal.ll_bitemporal_insert(
    'test_1.mentorship',
    'mentor_id, mentee_name, department, trainee',
    '3, ''Jane Smith'', ''HR'', 65000',
    temporal_relationships.timeperiod('2024-09-01', '2024-12-31'),
    temporal_relationships.timeperiod(now(), 'infinity')
);
