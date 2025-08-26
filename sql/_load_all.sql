begin;
set search_path to bitemporal_internal, test_1;

\ir ll_bitemporal_insert_with_coalesce.sql

commit;