CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_coalesce(
    p_schema_name text,
    p_table_name text,
    p_business_key text,
    p_business_value text,
    p_value_columns text[]
) RETURNS void AS $$
DECLARE
    v_table text := format('%I.%I', p_schema_name, p_table_name);
    v_current_row record;
    v_previous_row record;
    v_current_row_json json;
    v_new_effective temporal_relationships.timeperiod;
    v_value_condition text := '';
    v_column text;
    v_value text;
    v_insert_cols text;
    v_insert_vals text;
BEGIN
    -- Ambil record saat ini (paling baru & asserted aktif)
    EXECUTE format(
        'SELECT * FROM %s WHERE %I = %L AND now() <@ asserted ORDER BY lower(effective) DESC LIMIT 1',
        v_table, p_business_key, p_business_value
    )
    INTO v_current_row;

    IF v_current_row IS NULL THEN
        RAISE NOTICE 'No current record found for coalescing for % = %', p_business_key, p_business_value;
        RETURN;
    END IF;

    v_current_row_json := row_to_json(v_current_row);

    -- Bangun kondisi nilai value-equivalent (semua kolom nilai sama)
    FOREACH v_column IN ARRAY p_value_columns LOOP
        v_value := COALESCE(v_current_row_json ->> v_column, NULL);

        IF v_value_condition != '' THEN
            v_value_condition := v_value_condition || ' AND ';
        END IF;

        v_value_condition := v_value_condition || format('%I IS NOT DISTINCT FROM %L', v_column, v_value);
    END LOOP;

    -- Cari record sebelumnya yang nilainya sama dan waktu berdempetan
    EXECUTE format(
        'SELECT * FROM %s WHERE %I = %L AND %s AND upper(effective) = lower(%L::temporal_relationships.timeperiod) AND now() <@ asserted ORDER BY effective DESC LIMIT 1',
        v_table,
        p_business_key,
        p_business_value,
        v_value_condition,
        v_current_row.effective
    )
    INTO v_previous_row;

    -- Jika ditemukan, lakukan coalesce
    IF v_previous_row IS NOT NULL THEN
        v_new_effective := temporal_relationships.timeperiod(
            lower(v_previous_row.effective), 
            upper(v_current_row.effective)
        );

        -- Akhiri masa asserted dua record lama
        EXECUTE format(
            'UPDATE %s SET asserted = temporal_relationships.timeperiod(lower(asserted), now()) WHERE %I = %L AND effective IN (%L, %L)',
            v_table, p_business_key, p_business_value,
            v_previous_row.effective, v_current_row.effective
        );

        -- Bangun query INSERT record hasil coalesce
        v_insert_cols := format('%I', p_business_key);
        v_insert_vals := format('%L', p_business_value);

        FOREACH v_column IN ARRAY p_value_columns LOOP
            v_insert_cols := v_insert_cols || ', ' || format('%I', v_column);
            v_value := COALESCE(v_current_row_json ->> v_column, NULL);
            v_insert_vals := v_insert_vals || ', ' || format('%L', v_value);
        END LOOP;

        v_insert_cols := v_insert_cols || ', effective, asserted';
        v_insert_vals := v_insert_vals || format(', %L::temporal_relationships.timeperiod, %L::temporal_relationships.timeperiod',
                                                 v_new_effective, bitemporal_internal.current_asserted_time());

        -- Eksekusi query insert
        EXECUTE format(
            'INSERT INTO %s (%s) VALUES (%s)',
            v_table, v_insert_cols, v_insert_vals
        );

        RAISE NOTICE 'Coalesced inserted for % = %', p_business_key, p_business_value;
    ELSE
        RAISE NOTICE 'No coalescing done for % = %', p_business_key, p_business_value;
    END IF;
END;
$$ LANGUAGE plpgsql;
