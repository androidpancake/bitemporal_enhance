CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_insert_with_reference(
    p_schema_name text,
    p_table_name text,
    p_list_of_fields text,
    p_list_of_values text,
    p_effective temporal_relationships.timeperiod,
    p_asserted temporal_relationships.timeperiod,
    p_business_key text,
    p_business_value text,
    p_ref_table text,
    p_ref_key_field text,
    p_ref_key_value text,
    p_ref_effective_column text
) RETURNS integer
AS $$
DECLARE
    v_rowcount integer;
    v_table text := p_schema_name || '.' || p_table_name;
    v_ref_table text := p_schema_name || '.' || p_ref_table;
BEGIN
    -- Validasi: pastikan nilai referensi ditemukan dan effective (validity) berada dalam effective dari tabel referensi
    EXECUTE format(
        $f$
        SELECT 1
        FROM %s
        WHERE %I = %L
          AND now() <@ asserted
          AND %I @> %L::temporal_relationships.timeperiod
        LIMIT 1
        $f$,
        v_ref_table,                            -- schema & table
        p_ref_key_field,                     -- reference key field
        p_ref_key_value,                     -- reference key value
        p_ref_effective_column,              -- effective column in ref table
        p_effective::text                    -- cast to text then back in SQL
    )
    INTO v_rowcount;

    IF v_rowcount IS NULL THEN
        RAISE EXCEPTION 'ID % not valid or validity % not in %.', p_ref_key_value, p_effective, p_ref_table;
    END IF;

    -- Insert ke tabel utama
    SELECT bitemporal_internal.ll_bitemporal_insert(
        v_table,
        p_list_of_fields,
        p_list_of_values,
        p_effective,
        p_asserted
    ) INTO v_rowcount;

    IF v_rowcount < 0 THEN
        RAISE EXCEPTION 'Insert failed for % with values %', v_table, p_list_of_values;
    END IF;

    -- -- Coalesce jika insert berhasil
    -- IF v_rowcount > 0 THEN
    --     PERFORM bitemporal_internal.ll_bitemporal_coalesce(
    --         p_schema_name,
    --         p_table_name,
    --         p_business_key,
    --         p_business_value,
    --         p_value_columns
    --     );
    -- END IF;

    -- SELECT bitemporal_internal.ll_bitemporal_insert_with_coalesce(
    --     p_schema_name,
    --     p_table_name,
    --     p_list_of_fields,
    --     p_list_of_values,
    --     p_effective,
    --     p_asserted,
    --     p_business_key,
    --     p_business_value,
    --     p_value_columns
    -- ) INTO v_rowcount;

    -- IF v_rowcount < 0 THEN
    --     RAISE EXCEPTION 'Insert failed for % with values %', v_table, p_list_of_values;
    -- END IF;

    RETURN v_rowcount;
END;
$$ LANGUAGE plpgsql;