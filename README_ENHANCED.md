# pg_bitemporal_enhance

Enhanced bitemporal extension that integrates with the existing pg_bitemporal framework, adding automatic coalescing and optimized temporal aggregation capabilities.

## Overview

This extension enhances the existing pg_bitemporal framework with:

1. **Automatic Coalescing**: Merges adjacent, value-equivalent records to reduce storage and improve query performance
2. **Optimized Temporal Aggregation**: Pre-computes temporal intervals for efficient aggregation operations
3. **Enhanced Trigger Generation**: Provides functions to generate triggers with coalescing support
4. **Compatibility**: Maintains full compatibility with existing pg_bitemporal functions and conventions

## Installation

1. Ensure pg_bitemporal is installed and loaded
2. Install the enhancement extension:

```sql
CREATE EXTENSION pg_bitemporal_enhance;
```

## Key Features

### 1. Automatic Coalescing

The coalescing feature automatically merges adjacent records that have the same business values, reducing storage and improving query performance.

**Core Function:**
```sql
bitemporal_internal.ll_bitemporal_coalesce(
    p_schema_name text,
    p_table_name text,
    p_business_key text,
    p_business_value text,
    p_value_columns text[]
)
```

**Example Usage:**
```sql
-- Coalesce employment records for employee 'EMP001' based on name and department
SELECT bitemporal_internal.ll_bitemporal_coalesce(
    'public', 
    'employment_bt', 
    'employee_id', 
    'EMP001', 
    ARRAY['name', 'department']
);
```

### 2. Enhanced Insert with Coalescing

Automatically triggers coalescing after insert operations:

```sql
bitemporal_internal.ll_bitemporal_insert_with_coalesce(
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
```

**Example:**
```sql
-- Insert with automatic coalescing
SELECT bitemporal_internal.ll_bitemporal_insert_with_coalesce(
    'public',
    'employment_bt',
    'name, department, salary',
    '''John Doe'', ''IT'', 75000',
    temporal_relationships.timeperiod('2024-01-01', '2024-12-31'),
    temporal_relationships.timeperiod(now(), 'infinity'),
    'employee_id',
    'EMP001',
    ARRAY['name', 'department']
);
```

### 3. Optimized Temporal Aggregation

Pre-computes temporal intervals for efficient aggregation operations:

#### Temporal Count
```sql
bitemporal_internal.ll_temporal_count(
    p_schema_name text,
    p_table_name text
)
```

#### Temporal Max
```sql
bitemporal_internal.ll_temporal_max(
    p_schema_name text,
    p_table_name text,
    p_column_name text
)
```

#### Temporal Average
```sql
bitemporal_internal.ll_temporal_avg(
    p_schema_name text,
    p_table_name text,
    p_column_name text
)
```

**Example Usage:**
```sql
-- Get temporal count of employees over time
SELECT * FROM bitemporal_internal.ll_temporal_count('public', 'employment_bt');

-- Get maximum salary over time
SELECT * FROM bitemporal_internal.ll_temporal_max('public', 'employment_bt', 'salary');

-- Get average salary over time
SELECT * FROM bitemporal_internal.ll_temporal_avg('public', 'employment_bt', 'salary');
```

### 4. Enhanced Trigger Generation

Generate triggers that automatically handle coalescing:

```sql
bitemporal_internal.ll_generate_enhanced_insert_trigger(
    p_schema_name text,
    p_table_name text,
    p_business_key text,
    p_value_columns text[]
)
```

**Example:**
```sql
-- Generate enhanced insert trigger code
SELECT bitemporal_internal.ll_generate_enhanced_insert_trigger(
    'public',
    'employment_bt',
    'employee_id',
    ARRAY['name', 'department']
);
```

## Integration with Existing pg_bitemporal

### Schema Compatibility

The enhanced extension maintains compatibility with existing pg_bitemporal schemas:

- Uses `bitemporal_internal` schema for enhanced functions
- Uses `temporal_relationships.timeperiod` domain for time periods
- Follows existing naming conventions with `ll_` prefix

### Function Integration

Enhanced functions integrate seamlessly with existing pg_bitemporal functions:

```sql
-- Standard pg_bitemporal insert
SELECT bitemporal_internal.ll_bitemporal_insert(
    'employment_bt',
    'name, department, salary',
    '''John Doe'', ''IT'', 75000',
    temporal_relationships.timeperiod('2024-01-01', '2024-12-31'),
    temporal_relationships.timeperiod(now(), 'infinity')
);

-- Enhanced insert with coalescing
SELECT bitemporal_internal.ll_bitemporal_insert_with_coalesce(
    'public',
    'employment_bt',
    'name, department, salary',
    '''John Doe'', ''IT'', 75000',
    temporal_relationships.timeperiod('2024-01-01', '2024-12-31'),
    temporal_relationships.timeperiod(now(), 'infinity'),
    'employee_id',
    'EMP001',
    ARRAY['name', 'department']
);
```

## Performance Optimization

### GiST Indexes

For optimal performance with temporal aggregation, create GiST indexes on the effective column:

```sql
-- Create GiST index for temporal aggregation optimization
CREATE INDEX idx_gist_employment_effective ON employment_bt USING GIST (effective);
```

### Coalescing Benefits

- **Storage Reduction**: Merges adjacent records with same values
- **Query Performance**: Fewer records to scan in temporal queries
- **Data Integrity**: Maintains temporal consistency while reducing redundancy

## Example Workflow

### 1. Create Bitemporal Table
```sql
-- Use existing pg_bitemporal function
SELECT bitemporal_internal.ll_create_bitemporal_table(
    'employment_bt',
    'employee_id integer, name text, department text, salary numeric',
    'employee_id'
);
```

### 2. Create Performance Index
```sql
CREATE INDEX idx_gist_employment_effective ON employment_bt USING GIST (effective);
```

### 3. Insert with Coalescing
```sql
-- Insert multiple records for the same employee
SELECT bitemporal_internal.ll_bitemporal_insert_with_coalesce(
    'public', 'employment_bt',
    'employee_id, name, department, salary',
    '1, ''John Doe'', ''IT'', 75000',
    temporal_relationships.timeperiod('2024-01-01', '2024-06-30'),
    temporal_relationships.timeperiod(now(), 'infinity'),
    'employee_id', '1', ARRAY['name', 'department']
);

SELECT bitemporal_internal.ll_bitemporal_insert_with_coalesce(
    'public', 'employment_bt',
    'employee_id, name, department, salary',
    '1, ''John Doe'', ''IT'', 80000',
    temporal_relationships.timeperiod('2024-07-01', '2024-12-31'),
    temporal_relationships.timeperiod(now(), 'infinity'),
    'employee_id', '1', ARRAY['name', 'department']
);
```

### 4. Perform Temporal Aggregation
```sql
-- Get employee count over time
SELECT * FROM bitemporal_internal.ll_temporal_count('public', 'employment_bt');

-- Get maximum salary over time
SELECT * FROM bitemporal_internal.ll_temporal_max('public', 'employment_bt', 'salary');
```

## Migration from Standard pg_bitemporal

To migrate existing pg_bitemporal tables to use enhanced features:

1. **Install Extension**: `CREATE EXTENSION pg_bitemporal_enhance;`
2. **Add Indexes**: Create GiST indexes on effective columns
3. **Update Inserts**: Replace standard inserts with enhanced inserts
4. **Generate Triggers**: Use enhanced trigger generation for new tables

## Troubleshooting

### Common Issues

1. **Schema Not Found**: Ensure `bitemporal_internal` and `temporal_relationships` schemas exist
2. **Type Mismatch**: Use `temporal_relationships.timeperiod` instead of `tsrange`
3. **Performance Issues**: Create GiST indexes on effective columns
4. **Coalescing Not Working**: Check that value columns are correctly specified

### Debug Functions

```sql
-- Check if table is bitemporal
SELECT bitemporal_internal.ll_is_bitemporal_table('public.employment_bt');

-- List table fields
SELECT bitemporal_internal.ll_bitemporal_list_of_fields('public.employment_bt');
```

## API Reference

### Core Functions

| Function | Description |
|----------|-------------|
| `ll_bitemporal_coalesce()` | Merge adjacent value-equivalent records |
| `ll_bitemporal_insert_with_coalesce()` | Insert with automatic coalescing |
| `ll_temporal_count()` | Count records over time intervals |
| `ll_temporal_max()` | Maximum value over time intervals |
| `ll_temporal_avg()` | Average value over time intervals |
| `ll_generate_enhanced_insert_trigger()` | Generate enhanced insert triggers |

### Helper Functions

| Function | Description |
|----------|-------------|
| `current_asserted_time()` | Get current assertion time |
| `current_effective_time()` | Get current effective time |
| `ll_compute_temporal_intervals()` | Compute distinct temporal intervals |

## License

This extension follows the same license as the underlying pg_bitemporal framework. 