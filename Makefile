# Makefile for pg_bitemporal_enhance

# The extension name
EXTENSION = pg_bitemporal_enhance
# The SQL script file containing the extension's definition
DATA = pg_bitemporal_enhance--1.0.sql

# PG_CONFIG is a utility that provides information about the installed PostgreSQL version
PG_CONFIG ?= pg_config
# PGXS is the PostgreSQL extension building infrastructure
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
