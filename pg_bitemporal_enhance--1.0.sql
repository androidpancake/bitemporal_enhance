-- pg_bitemporal_enhance--1.0.sql
-- This script creates the unified bitemporal extension.
-- It integrates coalescing logic and optimizes temporal aggregation.

-- First, ensure the environment is clean.
\echo Use "CREATE EXTENSION pg_bitemporal_enhance" to load this file. \quit

-- We need the btree_gist extension for our GiST index on temporal ranges.
CREATE EXTENSION IF NOT EXISTS btree_gist;

--------------------------------------------------------------------------------
-- SECTION 1: CORE TYPES AND HELPER FUNCTIONS
-- Foundational elements, likely from the original pg_bitemporal.
--------------------------------------------------------------------------------

-- Bitemporal range type for validity and transaction times.
-- We assume standard tsrange (timestamp range) is used for both.
-- Let's define a helper to get the current transaction time.
CREATE OR REPLACE FUNCTION current_transaction_time()
RETURNS tsrange AS $$
BEGIN
    RETURN tsrange(transaction_timestamp(), 'infinity');
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------
-- SECTION 2: AUTOMATIC COALESCING LOGIC
-- This section directly addresses the first problem identified in the research.
-- We create a function to merge adjacent, value-equivalent records.
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bitemporal_coalesce(
    target_table regclass,
    pk_column TEXT,
    pk_value TEXT,
    value_columns TEXT[]
)
RETURNS void AS $$
DECLARE
    -- Dynamic SQL queries
    query TEXT;
    -- Variables to hold data from rows
    current_row RECORD;
    previous_row RECORD;
    new_validity tsrange;
BEGIN
    -- Construct the WHERE clause for value-equivalence
    -- e.g., "name" = 'David' AND "dept" = 'PS'
    query := format('SELECT * FROM %s WHERE %I = %L', target_table, pk_column, pk_value);
    EXECUTE query INTO current_row;

    -- Build the condition for finding value-equivalent rows
    -- e.g., "name" = current_row.name AND "dept" = current_row.dept
    -- This is a simplified example; a real implementation would need to handle different data types.
    -- For this example, we assume text-based value columns.
    -- A more robust solution would dynamically build this part.
    -- Let's assume for the "Employment" case: value_columns = ARRAY['Name', 'Dept']
    -- And pk_column = 'id' (assuming an id column exists)

    -- Find the immediately preceding record that is value-equivalent and its validity period meets the current one.
    -- This is a simplified search. A full implementation would be more complex.
    query := format(
        'SELECT * FROM %s WHERE "Name" = %L AND "Dept" = %L AND upper(validity) = lower(%L::tsrange) AND upper(transaction_time) = ''infinity'' ORDER BY validity DESC LIMIT 1',
        target_table,
        current_row."Name",
        current_row."Dept",
        current_row.validity
    );
    EXECUTE query INTO previous_row;

    -- If a preceding, adjacent, and value-equivalent record is found...
    IF previous_row IS NOT NULL THEN
        RAISE NOTICE 'Coalescing needed. Previous record found: %', previous_row;

        -- 1. Calculate the new, combined validity period.
        new_validity := tsrange(lower(previous_row.validity), upper(current_row.validity));

        -- 2. End the transaction time of the two old records.
        -- This marks them as historical.
        query := format(
            'UPDATE %s SET transaction_time = tsrange(lower(transaction_time), transaction_timestamp()) WHERE id IN (%s, %s)',
            target_table,
            previous_row.id,
            current_row.id
        );
        EXECUTE query;

        -- 3. Insert the new, coalesced record.
        -- This record represents the single, continuous period.
        -- We copy all data from the most recent row and just change the validity and transaction time.
        query := format(
            'INSERT INTO %s ("Name", "Dept", "Title", validity, transaction_time) VALUES (%L, %L, %L, %L, current_transaction_time())',
            target_table,
            current_row."Name",
            current_row."Dept",
            current_row."Title",
            new_validity
        );
        EXECUTE query;

        RAISE NOTICE 'Coalescing complete. New validity: %', new_validity;
    END IF;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------
-- SECTION 3: BITEMPORAL OPERATIONS WITH COALESCING
-- Refines Cynthia Rusadi's work by integrating the coalescing logic.
--------------------------------------------------------------------------------

-- Example: An INSERT function that automatically triggers coalescing.
CREATE OR REPLACE FUNCTION bitemporal_insert_with_coalesce(
    target_table regclass,
    new_data jsonb
)
RETURNS void AS $$
DECLARE
    insert_query TEXT;
    pk_value TEXT;
BEGIN
    -- 1. Perform the standard bitemporal insert.
    -- We assume the new_data JSONB has all necessary keys.
    -- A real function would have more robust error handling.
    insert_query := format(
        'INSERT INTO %s ("Name", "Dept", "Title", validity, transaction_time) VALUES (%L, %L, %L, %L::tsrange, current_transaction_time()) RETURNING id',
        target_table,
        new_data->>'Name',
        new_data->>'Dept',
        new_data->>'Title',
        new_data->>'validity'
    );
    EXECUTE insert_query INTO pk_value;

    -- 2. Trigger the coalescing function immediately after insert.
    -- We pass the table, primary key name, the new row's PK value, and the columns to check for value-equivalence.
    PERFORM bitemporal_coalesce(target_table, 'id', pk_value, ARRAY['Name', 'Dept']);
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------
-- SECTION 4: OPTIMIZED TEMPORAL AGGREGATION
-- Refines Aditya Bimawan's work by using indexing and pre-calculation.
-- This section directly addresses the second problem of performance.
--------------------------------------------------------------------------------

-- IMPORTANT USER ACTION:
-- For this to be efficient, a GiST index MUST be created on the validity column.
-- The user must run this command on their bitemporal table:
--
-- CREATE INDEX idx_gist_employment_validity ON employment USING GIST (validity);
--

-- Step 1: A function to compute the distinct time intervals ONCE.
CREATE OR REPLACE FUNCTION compute_temporal_intervals(
    target_table regclass,
    OUT interval_start timestamptz,
    OUT interval_end timestamptz
)
RETURNS SETOF record AS $$
BEGIN
    -- This query finds all unique start and end points from the validity periods
    -- and creates a set of distinct, non-overlapping intervals.
    -- This is the expensive operation we want to run only once.
    -- The GiST index on 'validity' will make this much faster.
    RETURN QUERY
    WITH points AS (
        SELECT lower(validity) AS p FROM public.employment WHERE lower(validity) IS NOT NULL
        UNION
        SELECT upper(validity) AS p FROM public.employment WHERE upper(validity) IS NOT NULL AND upper(validity) != 'infinity'
    ),
    intervals AS (
        SELECT p AS start_time, lead(p) OVER (ORDER BY p) AS end_time
        FROM points
    )
    SELECT start_time, end_time
    FROM intervals
    WHERE end_time IS NOT NULL;
END;
$$ LANGUAGE plpgsql;


-- Step 2: The optimized aggregation functions that use the pre-computed intervals.

-- Example: Temporal COUNT
CREATE OR REPLACE FUNCTION temporal_count(target_table regclass)
RETURNS TABLE("count" BIGINT, "start" timestamptz, "end" timestamptz) AS $$
DECLARE
    rec RECORD;
BEGIN
    -- Create a temporary table to hold the intervals.
    CREATE TEMP TABLE temp_intervals ON COMMIT DROP AS
    SELECT * FROM compute_temporal_intervals(target_table);

    -- Now, for each interval, run the aggregation.
    FOR rec IN SELECT * FROM temp_intervals LOOP
        RETURN QUERY EXECUTE format(
            'SELECT count(*), %L::timestamptz, %L::timestamptz
             FROM %s
             WHERE validity && tsrange(%L, %L, ''[)'')', -- Check for overlap
            rec.interval_start,
            rec.interval_end,
            target_table,
            rec.interval_start,
            rec.interval_end
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Example: Temporal MAX on a 'salary' column (assuming it's numeric)
CREATE OR REPLACE FUNCTION temporal_max_salary(target_table regclass)
RETURNS TABLE("max_salary" NUMERIC, "start" timestamptz, "end" timestamptz) AS $$
DECLARE
    rec RECORD;
BEGIN
    -- Re-use the same interval computation logic.
    CREATE TEMP TABLE temp_intervals ON COMMIT DROP AS
    SELECT * FROM compute_temporal_intervals(target_table);

    FOR rec IN SELECT * FROM temp_intervals LOOP
        RETURN QUERY EXECUTE format(
            'SELECT max(salary), %L::timestamptz, %L::timestamptz
             FROM %s
             WHERE validity && tsrange(%L, %L, ''[)'')',
            rec.interval_start,
            rec.interval_end,
            target_table,
            rec.interval_start,
            rec.interval_end
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

RAISE NOTICE 'pg_bitemporal_enhance version 1.0 loaded successfully.';

