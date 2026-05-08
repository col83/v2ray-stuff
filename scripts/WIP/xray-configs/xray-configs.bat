@echo off

cd /d "%~dp0"

powershell -ExecutionPolicy Bypass -File "xray-configs.ps1"

pause