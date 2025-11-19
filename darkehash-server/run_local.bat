@echo off
REM Run DarkeHash server locally without Docker (Windows)

echo Starting DarkeHash Server (Local Mode)
echo ======================================

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo Error: Python is not installed or not in PATH
    pause
    exit /b 1
)

REM Create directories
if not exist "data" mkdir data
if not exist "uploads\handshakes" mkdir uploads\handshakes
if not exist "uploads\logs" mkdir uploads\logs

REM Install dependencies if needed
python -c "import flask" >nul 2>&1
if errorlevel 1 (
    echo Installing dependencies...
    pip install --progress-bar off Flask==3.0.0 Werkzeug==3.0.1 gunicorn==21.2.0
    if errorlevel 1 (
        echo Failed to install with versions, trying without...
        pip install --progress-bar off Flask Werkzeug gunicorn
    )
)

REM Set environment variables
if exist .env (
    echo Loading configuration from .env...
    for /f "tokens=*" %%a in ('type .env ^| findstr /v "^#"') do set %%a
) else (
    echo Warning: .env file not found, using defaults
    set AUTH_USERNAME=darkepwn
    set AUTH_PASSWORD=dh2akf5ksdai44ad0y
    set PORT=8800
)

REM Set required variables
set DB_PATH=./data/darkehash.db
set UPLOAD_DIR=./uploads

echo.
echo Configuration:
echo   Port: %PORT%
echo   Username: %AUTH_USERNAME%
echo   Database: %DB_PATH%
echo   Uploads: %UPLOAD_DIR%
echo.

REM Try to run with gunicorn, fall back to Flask
gunicorn --version >nul 2>&1
if errorlevel 1 (
    echo Gunicorn not found, starting with Flask development server...
    python app.py
) else (
    echo Starting with gunicorn...
    gunicorn --bind 0.0.0.0:%PORT% --workers 2 --timeout 120 app:app
)

pause
