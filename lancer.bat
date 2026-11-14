@echo off
setlocal
title UniPlan

cd /d "%~dp0backend"

rem Utilise le venv du projet s'il existe, sinon Python du PATH.
set "PY=python"
if exist "%~dp0..\.venv\Scripts\python.exe" set "PY=%~dp0..\.venv\Scripts\python.exe"
if exist "%~dp0backend\.venv\Scripts\python.exe" set "PY=%~dp0backend\.venv\Scripts\python.exe"

"%PY%" -c "import fastapi, uvicorn" >nul 2>&1
if errorlevel 1 (
    echo Installation des dependances Python...
    "%PY%" -m pip install -r requirements.txt
    if errorlevel 1 goto erreur
)

if not exist "%~dp0frontend\build\web\index.html" (
    echo.
    echo L'interface web n'est pas encore compilee.
    echo Lancez d'abord : build_interface.bat
    echo.
    pause
    exit /b 1
)

echo.
echo Demarrage d'UniPlan sur http://127.0.0.1:8000/app/
echo La base SQLite est creee automatiquement au premier lancement.
echo.
start "UniPlan - serveur" "%PY%" -m uvicorn app.main:app --host 127.0.0.1 --port 8000
timeout /t 4 /nobreak >nul
start "" "http://127.0.0.1:8000/app/"
exit /b 0

:erreur
echo.
echo Echec de l'installation des dependances Python.
echo Verifiez que Python est installe et accessible dans le PATH.
pause
exit /b 1
