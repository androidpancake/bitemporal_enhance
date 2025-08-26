CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_update(
  p_table TEXT,
  p_list_of_fields text, -- fields to update
  p_list_of_values TEXT,  -- values to update with
  p_search_fields TEXT,  -- search fields
  p_search_values TEXT,  --  search values
  p_effective anyelement,  -- effective range of the update
  p_asserted temporal_relationships.timeperiod  -- assertion for the update
) RETURNS INTEGER AS
  $BODY$
    DECLARE
      v_rowcount INT := 0;
      v_list_of_fields_to_insert TEXT := ' ';
      v_table_attr TEXT[];
      v_serial_key TEXT;
      v_keys_old INT[];
      v_keys INT[];
      v_now timestamptz := now(); -- so that we can reference this time
    BEGIN
      IF NOT (SELECT * FROM bitemporal_internal.ll_is_data_type_correct(p_table, p_effective))
        THEN RETURN v_rowcount;
      END IF;

      -- IF LOWER(p_asserted) < v_now::date -- should we allow this precision?...
      --   OR UPPER(p_asserted) < 'infinity'
      --     THEN RAISE NOTICE 'Asserted interval starts in the future or has a finite end: %', p_asserted;
      --     RETURN v_rowcount;
      -- END IF;

      IF (SELECT p_table LIKE '%.%')
        THEN v_serial_key := (SELECT split_part(p_table, '.', 2)) || '_key';
      ELSE v_serial_key := p_table || '_key';
      END IF;

      v_table_attr := bitemporal_internal.ll_bitemporal_list_of_fields(p_table);
      IF array_length(v_table_attr, 1) = 0
        THEN RAISE NOTICE 'Empty list of fields for a table %', p_table;
        RETURN v_rowcount;
      END IF;

      v_list_of_fields_to_insert := ARRAY_TO_STRING(v_table_attr, ',', '');

      v_keys_old := (SELECT * FROM bitemporal_internal.ll_bitemporal_update_end_assertion(
        p_table,
        p_search_fields,
        p_search_values,
        p_effective,
        p_asserted,
        v_serial_key,
        v_list_of_fields_to_insert
      ));

      -- Insert new assertion with old values and new effective
      EXECUTE FORMAT(
        $i$
          WITH inst AS (
            INSERT INTO %s ( %s, effective, asserted )
              SELECT %s ,%L, %L
              FROM %s
              WHERE ( %s ) IN (%s )
            RETURNING %s
          )
          SELECT array_agg(%s)
          FROM inst
        $i$,
        p_table,
        v_list_of_fields_to_insert,
        v_list_of_fields_to_insert,
        p_effective,
        p_asserted,
        p_table,
        v_serial_key,
        COALESCE(ARRAY_TO_STRING(v_keys_old,','), 'NULL'),
        v_serial_key,
        v_serial_key
      ) INTO v_keys;

      -- Update new record(s) in new assertion rage with new values                                  
      EXECUTE FORMAT(
        $u$
          UPDATE %s SET (%s) =
            (SELECT %s) 
            WHERE ( %s ) IN ( %s )
        $u$,
        p_table,
        p_list_of_fields,
        p_list_of_values,
        v_serial_key,
        COALESCE(ARRAY_TO_STRING(v_keys,','), 'NULL')
      );

      GET DIAGNOSTICS v_rowcount := ROW_COUNT;  
      RETURN v_rowcount;
    END;
  $BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_update_end_assertion(
  p_table TEXT,
  p_search_fields TEXT,  -- search fields
  p_search_values TEXT,  --  search values
  p_effective temporal_relationships.timeperiod,
  p_asserted temporal_relationships.timeperiod,  -- assertion for the update
  v_serial_key TEXT,
  v_list_of_fields_to_insert TEXT
) RETURNS INTEGER[] AS
  $BODY$
    DECLARE
      v_keys_old INT[];
    BEGIN
      -- End assertion period for the old record(s)
      EXECUTE FORMAT(
        $u$
          WITH updt AS (
            UPDATE %s SET asserted = temporal_relationships.timeperiod(LOWER(asserted), LOWER(%L::temporal_relationships.timeperiod))
            WHERE ( %s )=( %s ) AND
              (temporal_relationships.is_overlaps(effective, %L)
                OR temporal_relationships.is_meets(effective::temporal_relationships.timeperiod, %L)
                OR temporal_relationships.has_finishes(effective::temporal_relationships.timeperiod, %L))
              AND now() <@ asserted
            RETURNING %s
          )
          SELECT array_agg(%s)
          FROM updt
        $u$,
        p_table,
        p_asserted,
        p_search_fields,
        p_search_values,
        p_effective,
        p_effective,
        p_effective,
        v_serial_key,
        v_serial_key
      ) INTO v_keys_old;

      -- Insert new assertion rage with old values and effective-ended
      EXECUTE FORMAT(
        $i$
          INSERT INTO %s ( %s, effective, asserted )
            SELECT %s, temporal_relationships.timeperiod(LOWER(effective), LOWER(%L::temporal_relationships.timeperiod)), %L
            FROM %s
            WHERE ( %s ) in ( %s )
        $i$,
        p_table,
        v_list_of_fields_to_insert,
        v_list_of_fields_to_insert,
        p_effective,
        p_asserted,
        p_table,
        v_serial_key,
        COALESCE(ARRAY_TO_STRING(v_keys_old,','), 'NULL')
      );
      
      RETURN v_keys_old;
    END;    
  $BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_update_end_assertion(
  p_table TEXT,
  p_search_fields TEXT,  -- search fields
  p_search_values TEXT,  --  search values
  p_effective timestamptz,
  p_asserted temporal_relationships.timeperiod,  -- assertion for the update
  v_serial_key TEXT,
  v_list_of_fields_to_insert TEXT
) RETURNS INTEGER[] AS
  $BODY$
    DECLARE
      v_keys_old INT[];
    BEGIN
      -- End assertion period for the old record(s)
      EXECUTE FORMAT(
        $u$
          WITH updt AS (
            UPDATE %s SET asserted = temporal_relationships.timeperiod(LOWER(asserted), LOWER(%L::temporal_relationships.timeperiod))
            WHERE ( %s )=( %s )
            RETURNING %s
          )
          SELECT array_agg(%s)
          FROM updt
        $u$,
        p_table,
        p_asserted,
        p_search_fields,
        p_search_values,
        v_serial_key,
        v_serial_key
      ) INTO v_keys_old;

      RETURN v_keys_old;
    END;    
  $BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_update(
  p_table TEXT,
  p_list_of_fields text, -- fields to update
  p_list_of_values TEXT,  -- values to update with
  p_search_fields TEXT,  -- search fields
  p_search_values TEXT,  --  search values
  p_effective anyelement  -- effective range of the update
) RETURNS INTEGER AS
  $BODY$
    BEGIN
      IF (SELECT * FROM bitemporal_internal.ll_is_data_type_correct(p_table, p_effective))
        THEN RETURN (
          SELECT * FROM bitemporal_internal.ll_bitemporal_update(
            p_table,
            p_list_of_fields,
            p_list_of_values,
            p_search_fields,
            p_search_values,
            p_effective,
            temporal_relationships.timeperiod(now(), 'infinity')
          )
        );
      ELSE RETURN 0;
      END IF;
    END;
  $BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_update(
  p_table TEXT,
  p_list_of_fields text, -- fields to update
  p_list_of_values TEXT,  -- values to update with
  p_search_fields TEXT,  -- search fields
  p_search_values TEXT  --  search values
) RETURNS INTEGER AS
  $BODY$
    DECLARE
      table_type TEXT;
    BEGIN
      table_type := (SELECT * FROM bitemporal_internal.ll_bitemporal_table_type(p_table));
      IF table_type = 'interval' THEN
        RETURN (
          SELECT * FROM bitemporal_internal.ll_bitemporal_update(
            p_table,
            p_list_of_fields,
            p_list_of_values,
            p_search_fields,
            p_search_values,
            temporal_relationships.timeperiod(now(), 'infinity'),
            temporal_relationships.timeperiod(now(), 'infinity')
          )
        );
      ELSE 
        RETURN (
          SELECT * FROM bitemporal_internal.ll_bitemporal_update(
            p_table,
            p_list_of_fields,
            p_list_of_values,
            p_search_fields,
            p_search_values,
            now(),
            temporal_relationships.timeperiod(now(), 'infinity')
          )
        );
      END IF;
   END;
  $BODY$
LANGUAGE plpgsql;