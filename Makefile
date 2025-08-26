# Makefile for pg_bitemporal_enhance extension
# Supports building, installing, testing, and development


# Configuration
EXTENSION_NAME = pg_bitemporal_enhance
EXTENSION_VERSION = 1.0
PSQL = psql
# PostgreSQL connection options
PSQL_OPTS = -U postgres -h localhost -p 5433
PG_BINDIR="C:/Program Files/PostgreSQL/17/bin"
PG_CONFIG = $(PG_BINDIR)/pg_config

# Database name for install/test targets (can be overridden: make install DB_NAME=your_database)
DB_NAME=bt_enhance


# Directories
BUILD_DIR = build
SQL_DIR = .
DOC_DIR = .

# Files
EXTENSION_SQL = $(EXTENSION_NAME)--$(EXTENSION_VERSION).sql
CONTROL_FILE = $(EXTENSION_NAME).control
TEST_FILE = test_bitemporal_operations.sql
ENHANCED_TEST_FILE = test_enhanced_extension.sql

# PostgreSQL configuration
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Default target
all: build

# Build the extension
build: $(BUILD_DIR)
	@echo "Building $(EXTENSION_NAME) extension..."
	@mkdir -p $(BUILD_DIR)
	@cp $(EXTENSION_SQL) $(BUILD_DIR)/
	@cp $(CONTROL_FILE) $(BUILD_DIR)/
	@echo "Extension built successfully in $(BUILD_DIR)/"

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Install the extension

install: build
	@echo "Installing $(EXTENSION_NAME) extension..."
	@if [ -d "$(BUILD_DIR)" ]; then \
		cp $(BUILD_DIR)/$(EXTENSION_SQL) $(shell $(PG_CONFIG) --sharedir)/extension/; \
		cp $(BUILD_DIR)/$(CONTROL_FILE) $(shell $(PG_CONFIG) --sharedir)/extension/; \
		echo "Extension installed successfully"; \
	else \
		echo "Error: Build directory not found. Run 'make build' first."; \
		exit 1; \
	fi
# 	@echo "Loading all SQL from pg_bitemporal/sql/_load_all.sql..."
# 	@if [ -z "$(DB_NAME)" ]; then \
# 		echo "Warning: DB_NAME not set. Skipping SQL load. To load, use: make install DB_NAME=your_database"; \
# 	else \
# 		$(PSQL) $(PSQL_OPTS) -d $(DB_NAME) -f pg_bitemporal/sql/_load_all.sql; \
# 		echo "Loaded SQL from pg_bitemporal/sql/_load_all.sql into $(DB_NAME)"; \
# 	fi

# Uninstall the extension
uninstall:
	@echo "Uninstalling $(EXTENSION_NAME) extension..."
	@rm -f $(shell $(PG_CONFIG) --sharedir)/extension/$(EXTENSION_SQL)
	@rm -f $(shell $(PG_CONFIG) --sharedir)/extension/$(CONTROL_FILE)
	@echo "Extension uninstalled successfully"

# Test the extension (requires PostgreSQL connection)
test: build
	@echo "Testing $(EXTENSION_NAME) extension..."
	@if [ -z "$(DB_NAME)" ]; then \
		echo "Error: DB_NAME not set. Use: make test DB_NAME=your_database"; \
		exit 1; \
	fi
	@echo "Running comprehensive bitemporal operations test..."
	@$(PSQL) $(PSQL_OPTS) -d $(DB_NAME) -f $(TEST_FILE)
	@echo "Test completed successfully"

# Test enhanced functionality
test-enhanced: build
	@echo "Testing enhanced functionality..."
	@if [ -z "$(DB_NAME)" ]; then \
		echo "Error: DB_NAME not set. Use: make test-enhanced DB_NAME=your_database"; \
		exit 1; \
	fi
	@echo "Running enhanced functionality test..."
	@$(PSQL) $(PSQL_OPTS) -d $(DB_NAME) -f $(ENHANCED_TEST_FILE)
	@echo "Enhanced test completed successfully"

# Run all tests
test-all: test test-enhanced
	@echo "All tests completed successfully"

# Create test database
create-test-db:
	@echo "Creating test database..."
	@if [ -z "$(DB_NAME)" ]; then \
		echo "Error: DB_NAME not set. Use: make create-test-db DB_NAME=your_database"; \
		exit 1; \
	fi
	@createdb $(DB_NAME)
	@echo "Test database '$(DB_NAME)' created successfully"

# Setup test environment (create DB and install extensions)
setup-test: create-test-db
	@echo "Setting up test environment..."
	@if [ -z "$(DB_NAME)" ]; then \
		echo "Error: DB_NAME not set. Use: make setup-test DB_NAME=your_database"; \
		exit 1; \
	fi
	@$(PSQL) $(PSQL_OPTS) -d $(DB_NAME) -c "CREATE EXTENSION IF NOT EXISTS pg_bitemporal;"
	@$(PSQL) $(PSQL_OPTS) -d $(DB_NAME) -c "CREATE EXTENSION IF NOT EXISTS $(EXTENSION_NAME);"
	@echo "Test environment setup completed"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@echo "Clean completed"

# Show extension information
info:
	@echo "Extension Information:"
	@echo "  Name: $(EXTENSION_NAME)"
	@echo "  Version: $(EXTENSION_VERSION)"
	@echo "  SQL File: $(EXTENSION_SQL)"
	@echo "  Control File: $(CONTROL_FILE)"
	@echo "  Test Files: $(TEST_FILE), $(ENHANCED_TEST_FILE)"
	@echo "  Build Directory: $(BUILD_DIR)"

# Show help
help:
	@echo "Available targets:"
	@echo "  build          - Build the extension"
	@echo "  install        - Install the extension"
	@echo "  uninstall      - Uninstall the extension"
	@echo "  test           - Run comprehensive bitemporal operations test"
	@echo "  test-enhanced  - Run enhanced functionality test"
	@echo "  test-all       - Run all tests"
	@echo "  create-test-db - Create test database"
	@echo "  setup-test     - Setup complete test environment"
	@echo "  clean          - Clean build artifacts"
	@echo "  info           - Show extension information"
	@echo "  help           - Show this help"
	@echo ""
	@echo "Usage examples:"
	@echo "  make build"
	@echo "  make install"
	@echo "  make setup-test DB_NAME=test_bitemporal"
	@echo "  make test DB_NAME=test_bitemporal"
	@echo "  make test-all DB_NAME=test_bitemporal"

# Development targets
dev-setup: setup-test
	@echo "Development environment ready"

dev-test: test-all
	@echo "Development tests completed"

# Documentation
docs:
	@echo "Generating documentation..."
	@if [ -f "README_ENHANCED.md" ]; then \
		echo "Documentation files found:"; \
		ls -la *.md; \
	else \
		echo "No documentation files found"; \
	fi

# Package the extension
package: build
	@echo "Packaging $(EXTENSION_NAME) extension..."
	@tar -czf $(EXTENSION_NAME)-$(EXTENSION_VERSION).tar.gz \
		$(BUILD_DIR)/$(EXTENSION_SQL) \
		$(BUILD_DIR)/$(CONTROL_FILE) \
		README_ENHANCED.md \
		MIGRATION_GUIDE.md \
		ADAPTATION_SUMMARY.md \
		$(TEST_FILE) \
		$(ENHANCED_TEST_FILE) \
		Makefile
	@echo "Package created: $(EXTENSION_NAME)-$(EXTENSION_VERSION).tar.gz"

# Check extension syntax
check-syntax:
	@echo "Checking SQL syntax..."
	@$(PSQL) -f $(EXTENSION_SQL) > /dev/null 2>&1 || \
		(echo "SQL syntax check failed"; exit 1)
	@echo "SQL syntax check passed"

# Validate extension files
validate: check-syntax
	@echo "Validating extension files..."
	@if [ ! -f "$(EXTENSION_SQL)" ]; then \
		echo "Error: $(EXTENSION_SQL) not found"; \
		exit 1; \
	fi
	@if [ ! -f "$(CONTROL_FILE)" ]; then \
		echo "Error: $(CONTROL_FILE) not found"; \
		exit 1; \
	fi
	@echo "Extension files validation passed"

# Quick install and test (all-in-one)
quick-test: build install setup-test test-all
	@echo "Quick test completed successfully"

# Show PostgreSQL configuration
pg-config:
	@echo "PostgreSQL Configuration:"
	@echo "  pg_config: $(shell $(PG_CONFIG) --bindir)/pg_config"
	@echo "  sharedir: $(shell $(PG_CONFIG) --sharedir)"
	@echo "  version: $(shell $(PG_CONFIG) --version)"

# Check dependencies
check-deps:
	@echo "Checking dependencies..."
	@which $(PG_CONFIG) > /dev/null || (echo "Error: pg_config not found"; exit 1)
	@which $(PSQL) > /dev/null || (echo "Error: psql not found"; exit 1)
	@echo "Dependencies check passed"

# Install with dependencies check
install-safe: check-deps validate install
	@echo "Safe installation completed"

# Development workflow
dev: check-deps validate build install-safe setup-test test-all
	@echo "Development workflow completed successfully"

# Production deployment
deploy: check-deps validate build install
	@echo "Production deployment completed"

# Show all available targets
list:
	@echo "Available targets:"
	@$(MAKE) -pRrn | sed -n '/^[a-zA-Z0-9][^ ]*:/p' | sort

.PHONY: all build install uninstall test test-enhanced test-all create-test-db setup-test clean info help dev-setup dev-test docs package check-syntax validate quick-test pg-config check-deps install-safe dev deploy list
