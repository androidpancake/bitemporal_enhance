@echo off
REM Windows batch script for pg_bitemporal_enhance extension
REM Provides similar functionality to the Makefile

setlocal enabledelayedexpansion

REM Configuration
set EXTENSION_NAME=pg_bitemporal_enhance
set EXTENSION_VERSION=1.0
set BUILD_DIR=build
set EXTENSION_SQL=%EXTENSION_NAME%--%EXTENSION_VERSION%.sql
set CONTROL_FILE=%EXTENSION_NAME%.control
set TEST_FILE=test_bitemporal_operations.sql
set ENHANCED_TEST_FILE=test_enhanced_extension.sql

REM Check if command is provided
if "%1"=="" (
    echo Usage: build.bat [command] [DB_NAME]
    echo.
    echo Available commands:
    echo   build          - Build the extension
    echo   install        - Install the extension
    echo   test           - Run comprehensive test
    echo   test-enhanced  - Run enhanced functionality test
    echo   setup-test     - Setup test environment
    echo   clean          - Clean build artifacts
    echo   info           - Show extension information
    echo   help           - Show this help
    echo.
    echo Examples:
    echo   build.bat build
    echo   build.bat setup-test test_bitemporal
    echo   build.bat test test_bitemporal
    exit /b 1
)

set COMMAND=%1
set DB_NAME=%2

REM Check dependencies
call :check_deps
if errorlevel 1 exit /b 1

REM Execute command
if "%COMMAND%"=="build" call :build
if "%COMMAND%"=="install" call :install
if "%COMMAND%"=="test" call :test
if "%COMMAND%"=="test-enhanced" call :test_enhanced
if "%COMMAND%"=="setup-test" call :setup_test
if "%COMMAND%"=="clean" call :clean
if "%COMMAND%"=="info" call :info
if "%COMMAND%"=="help" call :help
if "%COMMAND%"=="validate" call :validate
if "%COMMAND%"=="package" call :package

exit /b 0

:check_deps
echo Checking dependencies...
where pg_config >nul 2>&1
if errorlevel 1 (
    echo Error: pg_config not found
    echo Please install PostgreSQL development tools
    exit /b 1
)

where psql >nul 2>&1
if errorlevel 1 (
    echo Error: psql not found
    echo Please ensure PostgreSQL is installed and in PATH
    exit /b 1
)

echo Dependencies check passed
exit /b 0

:build
echo Building %EXTENSION_NAME% extension...
if not exist %BUILD_DIR% mkdir %BUILD_DIR%
copy %EXTENSION_SQL% %BUILD_DIR%\
copy %CONTROL_FILE% %BUILD_DIR%\
echo Extension built successfully in %BUILD_DIR%\
exit /b 0

:install
echo Installing %EXTENSION_NAME% extension...
if not exist %BUILD_DIR% (
    echo Error: Build directory not found. Run 'build.bat build' first.
    exit /b 1
)

for /f "tokens=*" %%i in ('pg_config --sharedir') do set SHAREDIR=%%i
copy %BUILD_DIR%\%EXTENSION_SQL% "%SHAREDIR%\extension\"
copy %BUILD_DIR%\%CONTROL_FILE% "%SHAREDIR%\extension\"
echo Extension installed successfully
exit /b 0

:test
echo Testing %EXTENSION_NAME% extension...
if "%DB_NAME%"=="" (
    echo Error: DB_NAME not set. Use: build.bat test your_database
    exit /b 1
)
echo Running comprehensive bitemporal operations test...
psql -d %DB_NAME% -f %TEST_FILE%
if errorlevel 1 (
    echo Test failed
    exit /b 1
)
echo Test completed successfully
exit /b 0

:test_enhanced
echo Testing enhanced functionality...
if "%DB_NAME%"=="" (
    echo Error: DB_NAME not set. Use: build.bat test-enhanced your_database
    exit /b 1
)
echo Running enhanced functionality test...
psql -d %DB_NAME% -f %ENHANCED_TEST_FILE%
if errorlevel 1 (
    echo Enhanced test failed
    exit /b 1
)
echo Enhanced test completed successfully
exit /b 0

:setup_test
echo Setting up test environment...
if "%DB_NAME%"=="" (
    echo Error: DB_NAME not set. Use: build.bat setup-test your_database
    exit /b 1
)

echo Creating test database...
createdb %DB_NAME%
if errorlevel 1 (
    echo Error: Failed to create database
    exit /b 1
)

echo Installing extensions...
psql -d %DB_NAME% -c "CREATE EXTENSION IF NOT EXISTS pg_bitemporal;"
if errorlevel 1 (
    echo Error: Failed to install pg_bitemporal
    exit /b 1
)

psql -d %DB_NAME% -c "CREATE EXTENSION IF NOT EXISTS %EXTENSION_NAME%;"
if errorlevel 1 (
    echo Error: Failed to install %EXTENSION_NAME%
    exit /b 1
)

echo Test environment setup completed
exit /b 0

:clean
echo Cleaning build artifacts...
if exist %BUILD_DIR% rmdir /s /q %BUILD_DIR%
echo Clean completed
exit /b 0

:info
echo Extension Information:
echo   Name: %EXTENSION_NAME%
echo   Version: %EXTENSION_VERSION%
echo   SQL File: %EXTENSION_SQL%
echo   Control File: %CONTROL_FILE%
echo   Test Files: %TEST_FILE%, %ENHANCED_TEST_FILE%
echo   Build Directory: %BUILD_DIR%
exit /b 0

:help
echo Available commands:
echo   build          - Build the extension
echo   install        - Install the extension
echo   test           - Run comprehensive bitemporal operations test
echo   test-enhanced  - Run enhanced functionality test
echo   setup-test     - Setup complete test environment
echo   clean          - Clean build artifacts
echo   info           - Show extension information
echo   help           - Show this help
echo   validate       - Validate extension files
echo   package        - Create distribution package
echo.
echo Usage examples:
echo   build.bat build
echo   build.bat install
echo   build.bat setup-test test_bitemporal
echo   build.bat test test_bitemporal
echo   build.bat test-enhanced test_bitemporal
exit /b 0

:validate
echo Validating extension files...
if not exist %EXTENSION_SQL% (
    echo Error: %EXTENSION_SQL% not found
    exit /b 1
)
if not exist %CONTROL_FILE% (
    echo Error: %CONTROL_FILE% not found
    exit /b 1
)
echo Extension files validation passed
exit /b 0

:package
echo Packaging %EXTENSION_NAME% extension...
call :build
if errorlevel 1 exit /b 1

echo Creating package...
powershell -Command "Compress-Archive -Path '%BUILD_DIR%\%EXTENSION_SQL%', '%BUILD_DIR%\%CONTROL_FILE%', 'README_ENHANCED.md', 'MIGRATION_GUIDE.md', 'ADAPTATION_SUMMARY.md', '%TEST_FILE%', '%ENHANCED_TEST_FILE%', 'build.bat' -DestinationPath '%EXTENSION_NAME%-%EXTENSION_VERSION%.zip' -Force"
if errorlevel 1 (
    echo Error: Failed to create package
    exit /b 1
)
echo Package created: %EXTENSION_NAME%-%EXTENSION_VERSION%.zip
exit /b 0 