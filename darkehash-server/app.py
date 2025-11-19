#!/usr/bin/env python3
"""
DarkeHash Server - Flask application for receiving Pwnagotchi handshake uploads
"""

import os
import sqlite3
import json
from datetime import datetime
from pathlib import Path
from functools import wraps
from flask import Flask, request, jsonify
from werkzeug.security import check_password_hash, generate_password_hash
from werkzeug.utils import secure_filename

# Configuration from environment variables
DB_PATH = os.environ.get('DB_PATH', '/app/data/darkehash.db')
UPLOAD_DIR = os.environ.get('UPLOAD_DIR', '/app/uploads')
AUTH_USERNAME = os.environ.get('AUTH_USERNAME', 'admin')
AUTH_PASSWORD_HASH = os.environ.get('AUTH_PASSWORD_HASH', '')
MAX_FILE_SIZE = int(os.environ.get('MAX_FILE_SIZE', 10 * 1024 * 1024))  # 10MB default

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = MAX_FILE_SIZE


def init_db():
    """Initialize the SQLite database"""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('PRAGMA journal_mode=WAL')

    with conn:
        # Handshakes table
        conn.execute('''
            CREATE TABLE IF NOT EXISTS handshakes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                filename TEXT NOT NULL,
                ssid TEXT,
                bssid TEXT,
                device_name TEXT,
                uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                file_size INTEGER,
                file_path TEXT NOT NULL,
                UNIQUE(device_name, filename, uploaded_at)
            )
        ''')

        # Indexes for handshakes
        conn.execute('''
            CREATE INDEX IF NOT EXISTS idx_handshakes_device
            ON handshakes (device_name)
        ''')
        conn.execute('''
            CREATE INDEX IF NOT EXISTS idx_handshakes_uploaded
            ON handshakes (uploaded_at)
        ''')

        # Status logs table
        conn.execute('''
            CREATE TABLE IF NOT EXISTS status_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                device_name TEXT NOT NULL,
                log_data TEXT,
                system_info TEXT,
                uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # Indexes for status logs
        conn.execute('''
            CREATE INDEX IF NOT EXISTS idx_status_device
            ON status_logs (device_name)
        ''')
        conn.execute('''
            CREATE INDEX IF NOT EXISTS idx_status_uploaded
            ON status_logs (uploaded_at)
        ''')

    conn.close()
    app.logger.info(f"Database initialized at {DB_PATH}")


def get_db():
    """Get database connection"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def require_auth(f):
    """Decorator for basic authentication"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth = request.authorization

        if not auth:
            return jsonify({'error': 'Authentication required'}), 401

        # Check username
        if auth.username != AUTH_USERNAME:
            return jsonify({'error': 'Invalid credentials'}), 401

        # Check password
        if AUTH_PASSWORD_HASH:
            # If hash is provided, use it
            if not check_password_hash(AUTH_PASSWORD_HASH, auth.password):
                return jsonify({'error': 'Invalid credentials'}), 401
        else:
            # Fallback to plain text comparison (not recommended for production)
            plain_password = os.environ.get('AUTH_PASSWORD', 'changeme')
            if auth.password != plain_password:
                return jsonify({'error': 'Invalid credentials'}), 401

        return f(*args, **kwargs)

    return decorated_function


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint (no auth required)"""
    try:
        # Check database connectivity
        conn = get_db()
        conn.execute('SELECT 1')
        conn.close()

        return jsonify({
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
            'version': '1.0.0'
        }), 200
    except Exception as e:
        return jsonify({
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 500


@app.route('/api/upload/handshake', methods=['POST'])
@require_auth
def upload_handshake():
    """
    Upload handshake file endpoint
    Expects: multipart/form-data with 'handshake' file
    Optional: ssid, bssid, device_name in form data
    """
    try:
        # Check if file is present
        if 'handshake' not in request.files:
            return jsonify({'error': 'No handshake file provided'}), 400

        file = request.files['handshake']

        if file.filename == '':
            return jsonify({'error': 'Empty filename'}), 400

        # Secure the filename
        filename = secure_filename(file.filename)

        # Extract metadata from form
        ssid = request.form.get('ssid', '')
        bssid = request.form.get('bssid', '')
        device_name = request.form.get('device_name', request.authorization.username)

        # Create storage path: uploads/handshakes/{device_name}/{YYYY-MM-DD}/
        today = datetime.now().strftime('%Y-%m-%d')
        storage_dir = Path(UPLOAD_DIR) / 'handshakes' / device_name / today
        storage_dir.mkdir(parents=True, exist_ok=True)

        # Handle duplicate filenames by appending timestamp
        file_path = storage_dir / filename
        if file_path.exists():
            name, ext = os.path.splitext(filename)
            timestamp = datetime.now().strftime('%H%M%S')
            filename = f"{name}_{timestamp}{ext}"
            file_path = storage_dir / filename

        # Save the file
        file.save(str(file_path))
        file_size = file_path.stat().st_size

        # Store metadata in database
        conn = get_db()
        cursor = conn.cursor()

        cursor.execute('''
            INSERT INTO handshakes (filename, ssid, bssid, device_name, file_size, file_path)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (filename, ssid, bssid, device_name, file_size, str(file_path)))

        conn.commit()
        upload_id = cursor.lastrowid
        conn.close()

        app.logger.info(
            f"Handshake uploaded: {filename} from {device_name} "
            f"(SSID: {ssid}, BSSID: {bssid}, Size: {file_size} bytes)"
        )

        return jsonify({
            'success': True,
            'upload_id': upload_id,
            'filename': filename,
            'device_name': device_name,
            'uploaded_at': datetime.now().isoformat(),
            'message': 'Handshake uploaded successfully'
        }), 200

    except Exception as e:
        app.logger.error(f"Error uploading handshake: {e}")
        return jsonify({
            'error': 'Upload failed',
            'details': str(e)
        }), 500


@app.route('/api/upload/status', methods=['POST'])
@require_auth
def upload_status():
    """
    Upload status and logs endpoint
    Expects: JSON payload with device_name, log_data, system_info
    """
    try:
        data = request.get_json()

        if not data:
            return jsonify({'error': 'No JSON payload provided'}), 400

        device_name = data.get('device_name', request.authorization.username)
        log_data = data.get('log_data', '')
        system_info = data.get('system_info', {})

        # Store in database
        conn = get_db()
        cursor = conn.cursor()

        cursor.execute('''
            INSERT INTO status_logs (device_name, log_data, system_info)
            VALUES (?, ?, ?)
        ''', (device_name, log_data, json.dumps(system_info)))

        conn.commit()
        status_id = cursor.lastrowid
        conn.close()

        # Optionally save logs to file
        if log_data and os.environ.get('SAVE_LOGS_TO_FILE', 'true').lower() == 'true':
            today = datetime.now().strftime('%Y-%m-%d')
            timestamp = datetime.now().strftime('%H%M%S')
            log_dir = Path(UPLOAD_DIR) / 'logs' / device_name / today
            log_dir.mkdir(parents=True, exist_ok=True)

            log_file = log_dir / f"status_{timestamp}.json"
            with open(log_file, 'w') as f:
                json.dump({
                    'device_name': device_name,
                    'timestamp': data.get('timestamp', datetime.now().isoformat()),
                    'log_data': log_data,
                    'system_info': system_info
                }, f, indent=2)

        app.logger.info(
            f"Status uploaded from {device_name} "
            f"(Log lines: {len(log_data.splitlines())}, "
            f"System info keys: {list(system_info.keys())})"
        )

        return jsonify({
            'success': True,
            'status_id': status_id,
            'device_name': device_name,
            'uploaded_at': datetime.now().isoformat(),
            'message': 'Status uploaded successfully'
        }), 200

    except Exception as e:
        app.logger.error(f"Error uploading status: {e}")
        return jsonify({
            'error': 'Upload failed',
            'details': str(e)
        }), 500


@app.route('/api/stats', methods=['GET'])
@require_auth
def get_stats():
    """Get upload statistics (optional endpoint)"""
    try:
        conn = get_db()
        cursor = conn.cursor()

        # Get handshake count by device
        cursor.execute('''
            SELECT device_name, COUNT(*) as count
            FROM handshakes
            GROUP BY device_name
        ''')
        handshake_counts = dict(cursor.fetchall())

        # Get total counts
        cursor.execute('SELECT COUNT(*) FROM handshakes')
        total_handshakes = cursor.fetchone()[0]

        cursor.execute('SELECT COUNT(*) FROM status_logs')
        total_status_logs = cursor.fetchone()[0]

        # Get recent uploads
        cursor.execute('''
            SELECT device_name, filename, ssid, bssid, uploaded_at
            FROM handshakes
            ORDER BY uploaded_at DESC
            LIMIT 10
        ''')
        recent = [dict(row) for row in cursor.fetchall()]

        conn.close()

        return jsonify({
            'total_handshakes': total_handshakes,
            'total_status_logs': total_status_logs,
            'handshake_counts': handshake_counts,
            'recent_uploads': recent,
            'timestamp': datetime.now().isoformat()
        }), 200

    except Exception as e:
        app.logger.error(f"Error getting stats: {e}")
        return jsonify({
            'error': 'Failed to get statistics',
            'details': str(e)
        }), 500


@app.errorhandler(413)
def request_entity_too_large(error):
    """Handle file too large error"""
    return jsonify({
        'error': 'File too large',
        'max_size': MAX_FILE_SIZE
    }), 413


if __name__ == '__main__':
    # Initialize database
    init_db()

    # Create upload directories
    os.makedirs(os.path.join(UPLOAD_DIR, 'handshakes'), exist_ok=True)
    os.makedirs(os.path.join(UPLOAD_DIR, 'logs'), exist_ok=True)

    # Run Flask app
    app.run(
        host='0.0.0.0',
        port=int(os.environ.get('PORT', 5000)),
        debug=os.environ.get('DEBUG', 'false').lower() == 'true'
    )
