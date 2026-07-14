@echo off

cd /d "%~dp0"

set "EXEC_SCRIPT=xray-configs"
powershell -ExecutionPolicy Bypass -File "%EXEC_SCRIPT%.ps1"

pause