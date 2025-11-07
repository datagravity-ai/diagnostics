@echo off
REM Anomalo Diagnostic Tool - Windows Batch Wrapper
REM This script helps Windows users run the diagnostic tool

echo ========================================================
echo     Anomalo Diagnostic Tool - Windows Helper
echo ========================================================
echo.
echo This script will help you run the Anomalo diagnostic tool on Windows.
echo.

REM Check if PowerShell is available
where powershell >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: PowerShell not found!
    echo.
    echo PowerShell is required to run this diagnostic tool.
    echo Please install PowerShell or use Windows 10/11 which includes PowerShell by default.
    echo.
    pause
    exit /b 1
)

echo Found PowerShell. Checking for required tools...
echo.

REM Check for kubectl
where kubectl >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo WARNING: kubectl not found. The script may not work properly.
    echo Please install kubectl to collect Kubernetes diagnostics.
    echo.
)

echo Downloading and running the diagnostic script...
echo.

REM Download and run the PowerShell script
powershell -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/datagravity-ai/diagnostics/main/generate-diag.ps1' -OutFile 'generate-diag.ps1'; .\generate-diag.ps1"

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
