@echo off

:: Check admin
net session >nul 2>&1
if not %errorlevel%==0 (
    powershell -Command "Start-Process wt.exe -ArgumentList 'powershell -NoExit -ExecutionPolicy Bypass -File ""%~dp0CashKiller-v8.ps1""' -Verb RunAs"
    exit /b
)

:: If already admin
wt.exe powershell -NoExit -ExecutionPolicy Bypass -File "%~dp0CashKiller-v8.ps1"
