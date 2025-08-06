-- Manual install script for pg_bitemporal_enhance
-- Jalankan seluruh file ini di DBeaver untuk debug error

-- Pastikan extension dependency sudah ada
CREATE EXTENSION IF NOT EXISTS btree_gist;
-- Jika pakai pg_bitemporal, pastikan juga sudah ada:
-- CREATE EXTENSION IF NOT EXISTS pg_bitemporal;

-- Buat schema jika belum ada
CREATE SCHEMA IF NOT EXISTS bitemporal_internal;
CREATE SCHEMA IF NOT EXISTS temporal_relationships;

-- =========================
-- 1. Helper Functions
-- =========================

CREATE OR REPLACE FUNCTION bitemporal_internal.current_asserted_time()
RETURNS temporal_relationships.timeperiod AS $$
BEGIN
    RETURN temporal_relationships.timeperiod(transaction_timestamp(), 'infinity');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bitemporal_internal.current_effective_time()
RETURNS temporal_relationships.timeperiod AS $$
BEGIN
    RETURN temporal_relationships.timeperiod(now(), 'infinity');
END;
$$ LANGUAGE plpgsql;

-- =========================
-- 2. Coalescing Logic
-- =========================

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

    v_query := format('SELECT * FROM %s WHERE %I = %L AND now() <@ asserted ORDER BY effective DESC LIMIT 1',
                     v_table, p_business_key, p_business_value);
    EXECUTE v_query INTO v_current_row;

    IF v_current_row IS NULL THEN
        RAISE NOTICE 'No current record found for coalescing';
        RETURN;
    END IF;

    FOREACH v_column IN ARRAY p_value_columns LOOP
        IF v_value_condition != '' THEN
            v_value_condition := v_value_condition || ' AND ';
        END IF;
        v_value_condition := v_value_condition || format('%I = %L', v_column, v_current_row.column_name);
    END LOOP;

    v_query := format(
        'SELECT * FROM %s WHERE %s AND upper(effective) = lower(%L::temporal_relationships.timeperiod) AND now() <@ asserted ORDER BY effective DESC LIMIT 1',
        v_table,
        v_value_condition,
        v_current_row.effective
    );
    EXECUTE v_query INTO v_previous_row;

    IF v_previous_row IS NOT NULL THEN
        RAISE NOTICE 'Coalescing needed. Previous record found: %', v_previous_row;

        v_new_effective := temporal_relationships.timeperiod(
            lower(v_previous_row.effective),
            upper(v_current_row.effective)
        );

        v_query := format(
            'UPDATE %s SET asserted = temporal_relationships.timeperiod(lower(asserted), now()) WHERE %I IN (%s, %s)',
            v_table,
            p_business_key,
            v_previous_row.column_name,
            v_current_row.column_name
        );
        EXECUTE v_query;

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

-- =========================
-- 3. (Lanjutkan dengan function lain sesuai file extension Anda)
-- =========================

-- Copy semua function lain dari file extension Anda ke sini,
-- PASTIKAN tidak ada RAISE NOTICE di luar function, tidak ada \echo, \quit, dsb.

-- =========================
-- END OF FILE
-- =========================

-- Setelah selesai, jalankan seluruh file ini di DBeaver.
-- Jika ada error, DBeaver akan menunjukkan baris errornya secara langsung.