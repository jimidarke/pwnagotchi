#!/bin/bash
# Run DarkeHash server locally without Docker

echo "Starting DarkeHash Server (Local Mode)"
echo "======================================"

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed"
    exit 1
fi

# Create directories
mkdir -p data uploads/handshakes uploads/logs

# Check if dependencies are installed
if ! python3 -c "import flask" 2>/dev/null; then
    echo "Installing dependencies..."
    pip3 install --progress-bar off Flask==3.0.0 Werkzeug==3.0.1 gunicorn==21.2.0 || {
        echo "Failed to install dependencies. Trying without versions..."
        pip3 install --progress-bar off Flask Werkzeug gunicorn
    }
fi

# Export environment variables from .env if it exists
if [ -f .env ]; then
    echo "Loading configuration from .env..."
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "Warning: .env file not found, using defaults"
    export AUTH_USERNAME=darkepwn
    export AUTH_PASSWORD=dh2akf5ksdai44ad0y
    export PORT=8800
fi

# Set required variables
export DB_PATH=./data/darkehash.db
export UPLOAD_DIR=./uploads

echo ""
echo "Configuration:"
echo "  Port: ${PORT}"
echo "  Username: ${AUTH_USERNAME}"
echo "  Database: ${DB_PATH}"
echo "  Uploads: ${UPLOAD_DIR}"
echo ""

# Check if gunicorn is available
if command -v gunicorn &> /dev/null; then
    echo "Starting with gunicorn..."
    gunicorn --bind 0.0.0.0:${PORT} --workers 2 --timeout 120 --access-logfile - --error-logfile - app:app
else
    echo "Gunicorn not found, starting with Flask development server..."
    python3 app.py
fi
