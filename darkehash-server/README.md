# DarkeHash Server

A Flask-based server for receiving handshake uploads and status reports from Pwnagotchi devices running the DarkeHash plugin.

## Features

- **Handshake Upload**: Receives and stores `.pcap` handshake files with metadata
- **Status Reporting**: Collects device logs and system statistics
- **Basic Authentication**: Secure uploads with HTTP Basic Auth
- **SQLite Database**: Tracks all uploads with metadata
- **File Organization**: Automatically organizes uploads by device and date
- **Dockerized**: Easy deployment with Docker Compose
- **Health Checks**: Built-in health monitoring endpoint

## Quick Start

### 1. Server Setup

```bash
# Clone or navigate to the darkehash-server directory
cd darkehash-server

# Copy environment template
cp .env.example .env

# Edit .env with your credentials
nano .env
```

Update the `.env` file with secure credentials:

```env
PORT=8800
AUTH_USERNAME=darkepwn
AUTH_PASSWORD=dh2akf5ksdai44ad0y
MAX_FILE_SIZE=10485760
SAVE_LOGS_TO_FILE=true
DEBUG=false
```

### 2. Start the Server

```bash
# Build and start with Docker Compose
docker-compose up -d

# Check logs
docker-compose logs -f

# Check health
curl http://localhost:8800/health
```

The server will be available at `http://localhost:8800`

### 3. Configure Pwnagotchi Plugin

On your Pwnagotchi device, edit `/etc/pwnagotchi/config.toml`:

```toml
[main.plugins.darkehash]
enabled = true
server_url = "http://155.138.136.208:8800"
username = "darkepwn"
password = "dh2akf5ksdai44ad0y"
upload_logs = true
log_lines = 200
max_retries = 3
show_status = false
```

**Note**: Server is configured at `155.138.136.208:8800`

### 4. Restart Pwnagotchi

```bash
sudo systemctl restart pwnagotchi
```

## API Endpoints

### POST /api/upload/handshake
Upload a handshake `.pcap` file.

**Authentication**: Basic Auth required

**Request**: `multipart/form-data`
- `handshake` (file): The `.pcap` file
- `ssid` (optional): Network SSID
- `bssid` (optional): Network BSSID
- `device_name` (optional): Device identifier

**Response**:
```json
{
  "success": true,
  "upload_id": 123,
  "filename": "NetworkName_AA-BB-CC-DD-EE-FF.pcap",
  "device_name": "pwnagotchi",
  "uploaded_at": "2025-01-15T10:30:00",
  "message": "Handshake uploaded successfully"
}
```

### POST /api/upload/status
Upload device status and logs.

**Authentication**: Basic Auth required

**Request**: JSON
```json
{
  "device_name": "my-pwny",
  "timestamp": "2025-01-15T10:30:00",
  "log_data": "Recent log entries...",
  "system_info": {
    "uptime": 86400,
    "version": "2.8.9",
    "handshakes_uploaded": 45,
    "handshakes_pending": 2
  }
}
```

**Response**:
```json
{
  "success": true,
  "status_id": 456,
  "device_name": "my-pwny",
  "uploaded_at": "2025-01-15T10:30:00",
  "message": "Status uploaded successfully"
}
```

### GET /api/stats
Get upload statistics (optional endpoint).

**Authentication**: Basic Auth required

**Response**:
```json
{
  "total_handshakes": 150,
  "total_status_logs": 75,
  "handshake_counts": {
    "device1": 100,
    "device2": 50
  },
  "recent_uploads": [...],
  "timestamp": "2025-01-15T10:30:00"
}
```

### GET /health
Health check endpoint (no authentication required).

**Response**:
```json
{
  "status": "healthy",
  "timestamp": "2025-01-15T10:30:00",
  "version": "1.0.0"
}
```

## File Storage

Uploaded files are organized as follows:

```
uploads/
├── handshakes/
│   └── {device_name}/
│       └── {YYYY-MM-DD}/
│           └── *.pcap
└── logs/
    └── {device_name}/
        └── {YYYY-MM-DD}/
            └── status_{HHMMSS}.json
```

## Database Schema

### handshakes Table
- `id`: Primary key
- `filename`: Original filename
- `ssid`: Network SSID
- `bssid`: Network BSSID
- `device_name`: Uploading device
- `uploaded_at`: Upload timestamp
- `file_size`: File size in bytes
- `file_path`: Storage path

### status_logs Table
- `id`: Primary key
- `device_name`: Device identifier
- `log_data`: Log entries (text)
- `system_info`: System information (JSON)
- `uploaded_at`: Upload timestamp

## Configuration Options

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Server port | `5000` |
| `AUTH_USERNAME` | Basic auth username | `admin` |
| `AUTH_PASSWORD` | Basic auth password | `changeme` |
| `AUTH_PASSWORD_HASH` | Password hash (preferred over plain) | - |
| `DB_PATH` | SQLite database path | `/app/data/darkehash.db` |
| `UPLOAD_DIR` | Upload storage directory | `/app/uploads` |
| `MAX_FILE_SIZE` | Maximum file size in bytes | `10485760` (10MB) |
| `SAVE_LOGS_TO_FILE` | Save logs as JSON files | `true` |
| `DEBUG` | Enable debug mode | `false` |

### Plugin Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `enabled` | Enable the plugin | `false` |
| `server_url` | Server base URL (required) | - |
| `username` | Basic auth username (required) | - |
| `password` | Basic auth password (required) | - |
| `upload_logs` | Upload logs with status | `true` |
| `log_lines` | Number of log lines to upload | `200` |
| `max_retries` | Max retry attempts for failed uploads | `3` |
| `show_status` | Show upload stats on display | `false` |

## Security Recommendations

1. **Use Strong Passwords**: Generate secure passwords for authentication
2. **Use HTTPS**: Deploy behind a reverse proxy with SSL/TLS (nginx, Caddy, Traefik)
3. **Use Password Hashes**: Generate with:
   ```bash
   python3 -c "from werkzeug.security import generate_password_hash; print(generate_password_hash('your_password'))"
   ```
4. **Firewall**: Restrict access to trusted IPs if possible
5. **Regular Backups**: Backup the database and uploads directory
6. **Monitor Logs**: Check `docker-compose logs` regularly for suspicious activity

## Reverse Proxy Example (nginx)

```nginx
server {
    listen 443 ssl http2;
    server_name darkehash.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Increase timeout for large file uploads
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
    }
}
```

## Troubleshooting

### Plugin Not Uploading

1. Check plugin is enabled: `grep darkehash /etc/pwnagotchi/config.toml`
2. Check Pwnagotchi logs: `tail -f /var/log/pwnagotchi.log | grep DARKEHASH`
3. Verify internet connectivity on Pwnagotchi
4. Test server connectivity: `curl -u username:password http://your-server:5000/health`

### Server Issues

```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs -f

# Restart server
docker-compose restart

# Check database
docker-compose exec darkehash-server sqlite3 /app/data/darkehash.db "SELECT COUNT(*) FROM handshakes;"
```

### Permission Errors

```bash
# Fix upload directory permissions
sudo chown -R 1000:1000 uploads/
sudo chmod -R 755 uploads/
```

## Maintenance

### View Database Stats

```bash
docker-compose exec darkehash-server sqlite3 /app/data/darkehash.db << EOF
SELECT COUNT(*) as total_handshakes FROM handshakes;
SELECT device_name, COUNT(*) as count FROM handshakes GROUP BY device_name;
SELECT COUNT(*) as total_status_logs FROM status_logs;
EOF
```

### Backup Database

```bash
# Backup database
cp data/darkehash.db data/darkehash.db.backup

# Or export to SQL
docker-compose exec darkehash-server sqlite3 /app/data/darkehash.db .dump > backup.sql
```

### Clean Old Logs

```bash
# Remove log files older than 30 days
find uploads/logs -name "*.json" -mtime +30 -delete
```

## Development

Run without Docker:

```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables
export AUTH_USERNAME=admin
export AUTH_PASSWORD=test123
export DB_PATH=./darkehash.db
export UPLOAD_DIR=./uploads

# Run development server
python app.py
```

## License

GPL3 - Same as Pwnagotchi project

## Support

For issues or questions:
- Check Pwnagotchi logs: `/var/log/pwnagotchi.log`
- Check server logs: `docker-compose logs`
- Review the troubleshooting section above
