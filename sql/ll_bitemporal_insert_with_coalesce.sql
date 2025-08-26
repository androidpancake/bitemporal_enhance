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
    v_table text := p_schema_name || '.' || p_table_name;
BEGIN
    -- 1. Perform the standard bitemporal insert
    SELECT bitemporal_internal.ll_bitemporal_insert(
        v_table,
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