-- pg_bitemporal_enhance--1.0.sql
-- This script creates the enhanced bitemporal extension that integrates with pg_bitemporal.
-- It adds coalescing logic and optimizes temporal aggregation while maintaining compatibility.

-- First, ensure the environment is clean.
-- \echo Use "CREATE EXTENSION pg_bitemporal_enhance" to load this file. \quit

-- We need the btree_gist extension for our GiST index on temporal ranges.
CREATE EXTENSION IF NOT EXISTS btree_gist;

DROP EXTENSION IF EXISTS pg_bitemporal_enhance CASCADE;

-- Ensure we have the required schemas
CREATE SCHEMA IF NOT EXISTS bitemporal_internal;
CREATE SCHEMA IF NOT EXISTS temporal_relationships;

GRANT USAGE ON SCHEMA bitemporal_internal TO public;
GRANT USAGE ON SCHEMA temporal_relationships TO public;
--------------------------------------------------------------------------------
-- SECTION 1: CORE HELPER FUNCTIONS
-- Enhanced functions that work with the existing pg_bitemporal framework
--------------------------------------------------------------------------------

-- Helper function to get current assertion time using pg_bitemporal conventions
CREATE OR REPLACE FUNCTION bitemporal_internal.current_asserted_time()
RETURNS temporal_relationships.timeperiod AS $$
BEGIN
    RETURN temporal_relationships.timeperiod(transaction_timestamp(), 'infinity');
END;
$$ LANGUAGE plpgsql;

-- Helper function to get current effective time
CREATE OR REPLACE FUNCTION bitemporal_internal.current_effective_time()
RETURNS temporal_relationships.timeperiod AS $$
BEGIN
    RETURN temporal_relationships.timeperiod(now(), 'infinity');
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------
-- SECTION 2: AUTOMATIC COALESCING LOGIC
-- Enhanced coalescing that works with pg_bitemporal's effective/asserted model
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_coalesce(
    p_schema_name text,
    p_table_name text,
    p_business_key text,
    p_business_value text,
    p_value_columns text[]
)
RETURNS void AS $$
DECLARE
    v_table text;
    v_query text;
    v_current_row record;
    v_previous_row record;
    v_new_effective temporal_relationships.timeperiod;
    v_value_condition text := '';
    v_column text;
BEGIN
    v_table := p_schema_name || '.' || p_table_name;
    
    -- Get the current record
    v_query := format('SELECT * FROM %s WHERE %I = %L AND now() <@ asserted ORDER BY effective DESC LIMIT 1', 
                     v_table, p_business_key, p_business_value);
    EXECUTE v_query INTO v_current_row;
    
    IF v_current_row IS NULL THEN
        RAISE NOTICE 'No current record found for coalescing';
        RETURN;
    END IF;
    
    -- Build value-equivalence condition dynamically
    FOREACH v_column IN ARRAY p_value_columns LOOP
        IF v_value_condition != '' THEN
            v_value_condition := v_value_condition || ' AND ';
        END IF;
        v_value_condition := v_value_condition || format('%I = %L', v_column, v_current_row.column_name);
    END LOOP;
    
    -- Find the immediately preceding record that is value-equivalent and adjacent
    v_query := format(
        'SELECT * FROM %s WHERE %s AND upper(effective) = lower(%L::temporal_relationships.timeperiod) AND now() <@ asserted ORDER BY effective DESC LIMIT 1',
        v_table,
        v_value_condition,
        v_current_row.effective
    );
    EXECUTE v_query INTO v_previous_row;
    
    -- If a preceding, adjacent, and value-equivalent record is found...
    IF v_previous_row IS NOT NULL THEN
        RAISE NOTICE 'Coalescing needed. Previous record found: %', v_previous_row;
        
        -- 1. Calculate the new, combined effective period
        v_new_effective := temporal_relationships.timeperiod(
            lower(v_previous_row.effective), 
            upper(v_current_row.effective)
        );
        
        -- 2. End the assertion time of the two old records
        v_query := format(
            'UPDATE %s SET asserted = temporal_relationships.timeperiod(lower(asserted), now()) WHERE %I IN (%s, %s)',
            v_table,
            p_business_key,
            v_previous_row.column_name,
            v_current_row.column_name
        );
        EXECUTE v_query;
        
        -- 3. Insert the new, coalesced record
        -- We need to dynamically build the INSERT statement based on the table structure
        v_query := format(
            'INSERT INTO %s SELECT %s, %L, %L FROM %s WHERE %I = %L LIMIT 1',
            v_table,
            bitemporal_internal.ll_bitemporal_list_of_fields(v_table),
            v_new_effective,
            bitemporal_internal.current_asserted_time(),
            v_table,
            p_business_key,
            v_current_row.column_name
        );
        EXECUTE v_query;
        
        RAISE NOTICE 'Coalescing complete. New effective period: %', v_new_effective;
    END IF;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------
-- SECTION 3: ENHANCED BITEMPORAL OPERATIONS WITH COALESCING
-- Enhanced insert function that automatically triggers coalescing
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_insert_with_coalesce(
    p_schema_name text,
    p_table_name text,
    p_list_of_fields text,
    p_list_of_values text,
    p_effective temporal_relationships.timeperiod,
    p_asserted temporal_relationships.timeperiod,
    p_business_key text,
    p_business_value text,
    p_value_columns text[]
)
RETURNS integer AS $$
DECLARE
    v_rowcount integer;
BEGIN
    -- 1. Perform the standard bitemporal insert
    SELECT bitemporal_internal.ll_bitemporal_insert(
        p_table_name,
        p_list_of_fields,
        p_list_of_values,
        p_effective,
        p_asserted
    ) INTO v_rowcount;
    
    -- 2. Trigger coalescing if insert was successful
    IF v_rowcount > 0 THEN
        PERFORM bitemporal_internal.ll_bitemporal_coalesce(
            p_schema_name,
            p_table_name,
            p_business_key,
            p_business_value,
            p_value_columns
        );
    END IF;
    
    RETURN v_rowcount;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------
-- SECTION 4: OPTIMIZED TEMPORAL AGGREGATION
-- Enhanced aggregation functions that work with pg_bitemporal's timeperiod type
--------------------------------------------------------------------------------

-- Function to compute distinct temporal intervals for a bitemporal table
CREATE OR REPLACE FUNCTION bitemporal_internal.ll_compute_temporal_intervals(
    p_schema_name text,
    p_table_name text,
    OUT interval_start temporal_relationships.time_endpoint,
    OUT interval_end temporal_relationships.time_endpoint
)
RETURNS SETOF record AS $$
DECLARE
    v_table text;
BEGIN
    v_table := p_schema_name || '.' || p_table_name;
    
    -- This query finds all unique start and end points from the effective periods
    -- and creates a set of distinct, non-overlapping intervals
    RETURN QUERY EXECUTE format(
        'WITH points AS (
            SELECT lower(effective) AS p FROM %s WHERE lower(effective) IS NOT NULL AND now() <@ asserted
            UNION
            SELECT upper(effective) AS p FROM %s WHERE upper(effective) IS NOT NULL AND upper(effective) != ''infinity'' AND now() <@ asserted
        ),
        intervals AS (
            SELECT p AS start_time, lead(p) OVER (ORDER BY p) AS end_time
            FROM points
        )
        SELECT start_time, end_time
        FROM intervals
        WHERE end_time IS NOT NULL',
        v_table, v_table
    );
END;
$$ LANGUAGE plpgsql;

-- Enhanced temporal COUNT function
CREATE OR REPLACE FUNCTION bitemporal_internal.ll_temporal_count(
    p_schema_name text,
    p_table_name text
)
RETURNS TABLE("count" bigint, "start" temporal_relationships.time_endpoint, "end" temporal_relationships.time_endpoint) AS $$
DECLARE
    v_table text;
    v_rec record;
BEGIN
    v_table := p_schema_name || '.' || p_table_name;
    
    -- Create a temporary table to hold the intervals
    CREATE TEMP TABLE temp_intervals ON COMMIT DROP AS
    SELECT * FROM bitemporal_internal.ll_compute_temporal_intervals(p_schema_name, p_table_name);
    
    -- For each interval, run the aggregation
    FOR v_rec IN SELECT * FROM temp_intervals LOOP
        RETURN QUERY EXECUTE format(
            'SELECT count(*), %L::temporal_relationships.time_endpoint, %L::temporal_relationships.time_endpoint
             FROM %s
             WHERE effective && temporal_relationships.timeperiod(%L, %L, ''[)'') AND now() <@ asserted',
            v_rec.interval_start,
            v_rec.interval_end,
            v_table,
            v_rec.interval_start,
            v_rec.interval_end
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Enhanced temporal MAX function for any numeric column
CREATE OR REPLACE FUNCTION bitemporal_internal.ll_temporal_max(
    p_schema_name text,
    p_table_name text,
    p_column_name text
)
RETURNS TABLE("max_value" numeric, "start" temporal_relationships.time_endpoint, "end" temporal_relationships.time_endpoint) AS $$
DECLARE
    v_table text;
    v_rec record;
BEGIN
    v_table := p_schema_name || '.' || p_table_name;
    
    -- Create a temporary table to hold the intervals
    CREATE TEMP TABLE temp_intervals ON COMMIT DROP AS
    SELECT * FROM bitemporal_internal.ll_compute_temporal_intervals(p_schema_name, p_table_name);
    
    FOR v_rec IN SELECT * FROM temp_intervals LOOP
        RETURN QUERY EXECUTE format(
            'SELECT max(%I), %L::temporal_relationships.time_endpoint, %L::temporal_relationships.time_endpoint
             FROM %s
             WHERE effective && temporal_relationships.timeperiod(%L, %L, ''[)'') AND now() <@ asserted',
            p_column_name,
            v_rec.interval_start,
            v_rec.interval_end,
            v_table,
            v_rec.interval_start,
            v_rec.interval_end
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Enhanced temporal AVG function for any numeric column
CREATE OR REPLACE FUNCTION bitemporal_internal.ll_temporal_avg(
    p_schema_name text,
    p_table_name text,
    p_column_name text
)
RETURNS TABLE("avg_value" numeric, "start" temporal_relationships.time_endpoint, "end" temporal_relationships.time_endpoint) AS $$
DECLARE
    v_table text;
    v_rec record;
BEGIN
    v_table := p_schema_name || '.' || p_table_name;
    
    -- Create a temporary table to hold the intervals
    CREATE TEMP TABLE temp_intervals ON COMMIT DROP AS
    SELECT * FROM bitemporal_internal.ll_compute_temporal_intervals(p_schema_name, p_table_name);
    
    FOR v_rec IN SELECT * FROM temp_intervals LOOP
        RETURN QUERY EXECUTE format(
            'SELECT avg(%I), %L::temporal_relationships.time_endpoint, %L::temporal_relationships.time_endpoint
             FROM %s
             WHERE effective && temporal_relationships.timeperiod(%L, %L, ''[)'') AND now() <@ asserted',
            p_column_name,
            v_rec.interval_start,
            v_rec.interval_end,
            v_table,
            v_rec.interval_start,
            v_rec.interval_end
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------
-- SECTION 5: ENHANCED TRIGGER GENERATION
-- Functions to generate enhanced triggers with coalescing support
--------------------------------------------------------------------------------

-- Function to generate enhanced insert trigger with coalescing
-- Replace the existing function with this fixed version
CREATE OR REPLACE FUNCTION bitemporal_internal.ll_generate_enhanced_insert_trigger(
    p_schema_name text,
    p_table_name text,
    p_business_key text,
    p_value_columns text[]
)
RETURNS text AS $$
DECLARE
    v_trigger_name text;
    v_function_name text;
    v_trigger_code text;
BEGIN
    v_trigger_name := p_table_name || '_enhanced_insert_trigger';
    v_function_name := p_table_name || '_enhanced_insert_function';
    
    v_trigger_code := format($trig$
CREATE OR REPLACE FUNCTION %s.%s()
RETURNS trigger AS $func$
DECLARE
    v_business_value text;
    v_value_list text := '';
    v_field_list text := '';
    v_rec record;
BEGIN
    -- Build field list and value list dynamically
    FOR v_rec IN SELECT column_name FROM information_schema.columns 
                 WHERE table_schema = %L AND table_name = %L 
                 AND column_name NOT IN ('effective', 'asserted')
                 ORDER BY ordinal_position LOOP
        IF v_field_list != '' THEN
            v_field_list := v_field_list || ',';
            v_value_list := v_value_list || ',';
        END IF;
        v_field_list := v_field_list || v_rec.column_name;
        v_value_list := v_value_list || format('%%L', NEW.column_name);
    END LOOP;
    
    -- Get business key value
    v_business_value := NEW.%I;
    
    -- Call enhanced insert with coalescing
    PERFORM bitemporal_internal.ll_bitemporal_insert_with_coalesce(
        %L, %L, v_field_list, v_value_list,
        NEW.effective, NEW.asserted,
        %L, v_business_value, %L
    );
    
    RETURN NULL;
END;
$func$ LANGUAGE plpgsql;

CREATE TRIGGER %s
    INSTEAD OF INSERT ON %s.%s
    FOR EACH ROW EXECUTE FUNCTION %s.%s();
$trig$,
        p_schema_name, v_function_name,
        p_schema_name, p_table_name,
        p_business_key,
        p_schema_name, p_table_name,
        p_business_key, p_value_columns,
        v_trigger_name, p_schema_name, p_table_name,
        p_schema_name, v_function_name
    );
    
    RETURN v_trigger_code;
END;
$$ LANGUAGE plpgsql;


