@echo off
setlocal
echo Compilation de l'interface UniPlan...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0frontend\build_web.ps1"
if errorlevel 1 (
    echo.
    echo La compilation a echoue.
    pause
    exit /b 1
)
echo.
echo Interface prete dans frontend\build\web.
pause
