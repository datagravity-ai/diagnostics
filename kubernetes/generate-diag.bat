@echo off
REM Anomalo Diagnostic Tool - Windows Batch Wrapper
REM This script helps Windows users run the diagnostic tool

echo ========================================================
echo     Anomalo Diagnostic Tool - Windows Helper
echo ========================================================
echo.
echo This script will help you run the Anomalo diagnostic tool on Windows.
echo.

REM Check if we're in a supported environment
where bash >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: bash command not found!
    echo.
    echo Please install one of the following:
    echo 1. Windows Subsystem for Linux (WSL2) - Recommended
    echo 2. Git for Windows (includes Git Bash)
    echo 3. Docker Desktop
    echo.
    echo Then run this script again from that environment.
    echo.
    pause
    exit /b 1
)

echo Found bash environment. Checking for required tools...
echo.

REM Check for curl
where curl >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo WARNING: curl not found. The script may not work properly.
    echo Please install curl or use WSL2.
    echo.
)

REM Check for zip
where zip >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo WARNING: zip not found. The script may not work properly.
    echo Please install zip or use WSL2.
    echo.
)

echo Downloading and running the diagnostic script...
echo.

REM Download and run the script
bash -c "curl https://raw.githubusercontent.com/datagravity-ai/diagnostics/main/kubernetes/generate-diag.sh -o generate-diag.sh && chmod +x generate-diag.sh && ./generate-diag.sh"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================================
    echo Diagnostic collection completed successfully!
    echo Check the current directory for the generated ZIP file.
    echo ========================================================
) else (
    echo.
    echo ========================================================
    echo Diagnostic collection failed!
    echo Please check the error messages above and try again.
    echo ========================================================
)

echo.
pause
