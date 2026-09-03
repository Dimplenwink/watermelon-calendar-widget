@echo off
setlocal EnableExtensions
title Install Watermelon Calendar Widget
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
set "INSTALL_RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %INSTALL_RESULT%
