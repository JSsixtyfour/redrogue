@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_engine\convert.ps1" "%~1"
pause
