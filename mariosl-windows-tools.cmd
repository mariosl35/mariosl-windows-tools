@echo off
title MARIOSL Windows Tools

net session >nul 2>&1

if %errorlevel% neq 0 (
    powershell.exe -NoProfile -Command ^
        "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

cd /d "%~dp0too_many_damn_scripts_here"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0too_many_damn_scripts_here\ui\MainWindow.ps1"

exit /b %errorlevel%