-- pg_bitemporal_enhance--1.0.sql
-- This script creates the enhanced bitemporal extension that integrates with pg_bitemporal.
-- It adds coalescing logic and optimizes temporal aggregation while maintaining compatibility.

-- First, ensure the environment is clean.
-- \echo Use "CREATE EXTENSION pg_bitemporal_enhance" to load this file. \quit

-- We need the btree_gist extension for our GiST index on temporal ranges.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- DROP EXTENSION IF EXISTS pg_bitemporal_enhance CASCADE;


ALTER EXTENSION pg_bitemporal_enhance ADD SCHEMA bitemporal_internal;
ALTER EXTENSION pg_bitemporal_enhance ADD SCHEMA temporal_relationships;

GRANT USAGE ON SCHEMA bitemporal_internal TO public;
GRANT USAGE ON SCHEMA temporal_relationships TO public;

ALTER EXTENSION pg_bitemporal_enhance ADD FUNCTION bitemporal_internal.current_asserted_time();
ALTER EXTENSION pg_bitemporal_enhance ADD FUNCTION bitemporal_internal.current_effective_time();

ALTER EXTENSION pg_bitemporal_enhance
  ADD FUNCTION bitemporal_internal.ll_bitemporal_coalesce(text,text,text,text,text[]);
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
    p_schema_name    text,
    p_table_name     text,
    p_business_key   text,
    p_business_value text,
    p_value_columns  text[]
)
RETURNS void AS $$
DECLARE
    v_table            text;
    v_query            text;

    -- batas rantai yang akan digabung
    v_chain_lower      temporal_relationships.time_endpoint;
    v_chain_upper      temporal_relationships.time_endpoint;

    -- row saat ini & sebelumnya
    v_current_row      record;
    v_previous_row     record;

    -- nilai-nilai kolom untuk syarat kesetaraan
    v_current_row_json json;
    v_value_condition  text := '';
    v_column           text;
    v_value            text;

    -- daftar effective yang harus ditutup (literal), dipisah koma
    v_effectives_to_close text := '';

    -- hasil gabungan
    v_new_effective    temporal_relationships.timeperiod;

    -- untuk INSERT
    v_insert_cols      text;
    v_insert_vals      text;
BEGIN
    v_table := format('%I.%I', p_schema_name, p_table_name);

    ----------------------------------------------------------------
    -- (1) Ambil current row (paling baru, masih asserted sekarang)
    ----------------------------------------------------------------
    v_query := format(
        'SELECT * FROM %s
          WHERE %I = %L
            AND now() <@ asserted
         ORDER BY lower(effective) DESC
         LIMIT 1',
        v_table, p_business_key, p_business_value
    );
    EXECUTE v_query INTO v_current_row;

    IF v_current_row IS NULL THEN
        RAISE NOTICE 'No current record found for coalescing for % = %',
            p_business_key, p_business_value;
        RETURN;
    END IF;

    v_current_row_json := row_to_json(v_current_row);

    -- Inisialisasi rantai dengan current row
    v_chain_lower := lower(v_current_row.effective);
    v_chain_upper := upper(v_current_row.effective);
    v_effectives_to_close := format('%L::temporal_relationships.timeperiod',
                                    v_current_row.effective);

    ----------------------------------------------------------------
    -- (2) Build value-equivalence (null-safe, sekali per kolom)
    ----------------------------------------------------------------
    v_value_condition := '';
    FOREACH v_column IN ARRAY p_value_columns LOOP
        v_value := v_current_row_json ->> v_column; -- text or NULL
        IF v_value_condition <> '' THEN
            v_value_condition := v_value_condition || ' AND ';
        END IF;
        -- bandingkan sebagai text, null-safe
        v_value_condition := v_value_condition
          || format('(%I)::text IS NOT DISTINCT FROM %L', v_column, v_value);
    END LOOP;

    ----------------------------------------------------------------
    -- (3) LOOP: mundur terus cari previous yang adjacent & equal
    ----------------------------------------------------------------
    LOOP
        v_query := format(
            'SELECT * FROM %s
               WHERE %I = %L
                 AND %s
                 AND upper(effective) = %L
             ORDER BY lower(effective) DESC
             LIMIT 1',
            v_table,
            p_business_key, p_business_value,
            v_value_condition,
            v_chain_lower  -- cari yang menempel tepat di kiri
        );
        EXECUTE v_query INTO v_previous_row;

        EXIT WHEN v_previous_row IS NULL;

        -- extend rantai ke kiri
        v_chain_lower := lower(v_previous_row.effective);
        v_effectives_to_close := v_effectives_to_close || ', '
          || format('%L::temporal_relationships.timeperiod',
                    v_previous_row.effective);
    END LOOP;

    -- Jika tidak ada previous yang match, tidak ada coalesce dilakukan
    IF v_chain_lower = lower(v_current_row.effective) THEN
        RAISE NOTICE 'No adjacent, value-equivalent record found to coalesce for % = %',
            p_business_key, p_business_value;
        RETURN;
    END IF;

    ----------------------------------------------------------------
    -- (4) Tutup semua segmen lama dalam rantai
    ----------------------------------------------------------------
    v_query := format(
        'UPDATE %s
            SET asserted = temporal_relationships.timeperiod(lower(asserted), now())
          WHERE %I = %L
            AND effective IN (%s)',
        v_table,
        p_business_key, p_business_value,
        v_effectives_to_close
    );
    EXECUTE v_query;

    ----------------------------------------------------------------
    -- (5) INSERT satu record hasil gabungan dari v_chain_lower..v_chain_upper
    ----------------------------------------------------------------
    v_new_effective := temporal_relationships.timeperiod(v_chain_lower, v_chain_upper);

    -- kolom-kolom
    v_insert_cols := format('%I', p_business_key);
    FOREACH v_column IN ARRAY p_value_columns LOOP
        v_insert_cols := v_insert_cols || ', ' || format('%I', v_column);
    END LOOP;
    v_insert_cols := v_insert_cols || ', effective, asserted';

    -- nilainya mengikuti current row (karena value-equivalent sepanjang rantai)
    v_insert_vals := format('%L', p_business_value);
    FOREACH v_column IN ARRAY p_value_columns LOOP
        v_value := v_current_row_json ->> v_column;
        v_insert_vals := v_insert_vals || ', ' || format('%L', v_value);
    END LOOP;

    v_insert_vals := v_insert_vals
        || format(', %L::temporal_relationships.timeperiod, %L::temporal_relationships.timeperiod',
                  v_new_effective, bitemporal_internal.current_asserted_time());

    v_query := format('INSERT INTO %s (%s) VALUES (%s)',
                      v_table, v_insert_cols, v_insert_vals);
    EXECUTE v_query;

    RAISE NOTICE 'Coalesced chain for % = % into [% - %]',
                 p_business_key, p_business_value, v_chain_lower, v_chain_upper;

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
    ELSE
        RAISE NOTICE 'No rows inserted for % in %', p_business_value, p_table_name;
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
        SELECT start_time::temporal_relationships.time_endpoint, 
               end_time::temporal_relationships.time_endpoint
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
             WHERE effective && temporal_relationships.timeperiod(%L::temporal_relationships.time_endpoint, %L::temporal_relationships.time_endpoint) AND now() <@ asserted',
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
             WHERE effective && temporal_relationships.timeperiod(%L, %L) AND now() <@ asserted',
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


