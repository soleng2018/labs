@echo off
setlocal enabledelayedexpansion

:: Check if two parameters are provided
if "%~2"=="" (
    echo Usage: %0 ^<min_time_minutes^> ^<max_time_minutes^>
    echo Example: %0 5 15
    exit /b 1
)

set MIN_TIME=%1
set MAX_TIME=%2

:: Validate that min_time is less than max_time
if %MIN_TIME% GEQ %MAX_TIME% (
    echo Error: Minimum time must be less than maximum time
    exit /b 1
)

:: Validate that inputs are positive numbers
if %MIN_TIME% LEQ 0 (
    echo Error: Minimum time must be greater than 0
    exit /b 1
)

if %MAX_TIME% LEQ 0 (
    echo Error: Maximum time must be greater than 0
    exit /b 1
)

echo Starting continuous speedtest...
echo Min interval: %MIN_TIME% minutes
echo Max interval: %MAX_TIME% minutes
echo Press Ctrl+C to stop
echo.

:loop
    :: Calculate random wait time between min and max minutes
    set /a "range=(%MAX_TIME% - %MIN_TIME%) + 1"
    set /a "wait_minutes=(%RANDOM% %% %range%) + %MIN_TIME%"
    set /a "wait_seconds=%wait_minutes% * 60"
    
    echo Waiting %wait_minutes% minutes before next speedtest...
    
    :: Wait for the calculated time
    timeout /t %wait_seconds% /nobreak >nul
    
    :: Get current timestamp using PowerShell (works on all modern Windows)
    for /f "usebackq delims=" %%i in (`powershell -command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"`) do set timestamp=%%i
    
    echo [%timestamp%] Running speedtest...
    
    :: Run speedtest command (use speedtest.exe to avoid conflict with script name)
    speedtest.exe
    echo.
    
goto loop