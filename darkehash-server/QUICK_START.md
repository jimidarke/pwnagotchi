# DarkeHash Server - Quick Start Guide

Choose the method that works best for your environment:

## Option 1: Run Without Docker (RECOMMENDED - Easiest)

### Linux/Mac:
```bash
cd darkehash-server
./run_local.sh
```

### Windows:
```cmd
cd darkehash-server
run_local.bat
```

The script will:
- Install Python dependencies automatically
- Create required directories
- Load configuration from `.env`
- Start the server on port 8800

**Test it:**
```bash
curl http://localhost:8800/health
```

---

## Option 2: Docker with Fixed Dockerfile

```bash
cd darkehash-server

# Clean everything
docker-compose down -v
docker system prune -af

# Build with fixed Dockerfile (no progress bar)
docker-compose build --no-cache
docker-compose up -d

# Check logs
docker-compose logs -f
```

---

## Option 3: Docker with Alpine (Lighter)

```bash
cd darkehash-server

# Use Alpine-based Dockerfile
docker-compose down -v
docker-compose build --no-cache -f Dockerfile.alpine
docker-compose up -d

# Or modify docker-compose.yml to use Dockerfile.alpine
```

To use Alpine permanently, edit `docker-compose.yml`:
```yaml
services:
  darkehash-server:
    build:
      context: .
      dockerfile: Dockerfile.alpine  # Add this line
```

---

## Option 4: Manual Installation

If all else fails, install manually:

```bash
cd darkehash-server

# Install Python dependencies
pip3 install Flask Werkzeug gunicorn

# Create directories
mkdir -p data uploads/handshakes uploads/logs

# Set environment variables (Linux/Mac)
export AUTH_USERNAME=darkepwn
export AUTH_PASSWORD=dh2akf5ksdai44ad0y
export PORT=8800
export DB_PATH=./data/darkehash.db
export UPLOAD_DIR=./uploads

# Run with Python
python3 app.py

# OR run with gunicorn (production)
gunicorn --bind 0.0.0.0:8800 --workers 2 --timeout 120 app:app
```

---

## Verify Server is Running

### Test health endpoint:
```bash
curl http://localhost:8800/health
```

Expected response:
```json
{
  "status": "healthy",
  "timestamp": "2025-01-15T10:30:00",
  "version": "1.0.0"
}
```

### Test authentication:
```bash
curl -u darkepwn:dh2akf5ksdai44ad0y http://localhost:8800/api/stats
```

### Run full test suite:
```bash
python3 test_upload.py
```

---

## Troubleshooting

### Server won't start
```bash
# Check if port 8800 is already in use
netstat -tuln | grep 8800

# Or use a different port
export PORT=9000
```

### Permission errors
```bash
# Linux: Fix directory permissions
chmod -R 755 data uploads

# Windows: Run as administrator
```

### Missing dependencies
```bash
# Install specific versions
pip3 install Flask==3.0.0 Werkzeug==3.0.1 gunicorn==21.2.0

# Or latest versions
pip3 install Flask Werkzeug gunicorn
```

### Can't access from external network
```bash
# Check firewall
sudo ufw status
sudo ufw allow 8800/tcp

# Or on Windows Firewall
# Add inbound rule for port 8800
```

---

## Configuration

The server uses these environment variables (from `.env` file):

```env
PORT=8800
AUTH_USERNAME=darkepwn
AUTH_PASSWORD=dh2akf5ksdai44ad0y
MAX_FILE_SIZE=10485760
SAVE_LOGS_TO_FILE=true
DEBUG=false
```

---

## Next Steps

Once the server is running:

1. **Test externally:**
   ```bash
   curl http://155.138.136.208:8800/health
   ```

2. **Configure Pwnagotchi** - Add to `/etc/pwnagotchi/config.toml`:
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

3. **Restart Pwnagotchi:**
   ```bash
   sudo systemctl restart pwnagotchi
   ```

4. **Monitor uploads:**
   ```bash
   # Check database
   sqlite3 data/darkehash.db "SELECT COUNT(*) FROM handshakes;"

   # Check files
   ls -lh uploads/handshakes/
   ```

---

## Running as a Service (Linux)

To run the server automatically on boot:

**Create service file:**
```bash
sudo nano /etc/systemd/system/darkehash.service
```

**Add:**
```ini
[Unit]
Description=DarkeHash Server
After=network.target

[Service]
Type=simple
User=yourusername
WorkingDirectory=/path/to/darkehash-server
Environment="AUTH_USERNAME=darkepwn"
Environment="AUTH_PASSWORD=dh2akf5ksdai44ad0y"
Environment="PORT=8800"
Environment="DB_PATH=/path/to/darkehash-server/data/darkehash.db"
Environment="UPLOAD_DIR=/path/to/darkehash-server/uploads"
ExecStart=/usr/bin/python3 /path/to/darkehash-server/app.py
Restart=always

[Install]
WantedBy=multi-user.target
```

**Enable and start:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable darkehash
sudo systemctl start darkehash
sudo systemctl status darkehash
```

---

## Summary

**Easiest method:** Run `./run_local.sh` (Linux/Mac) or `run_local.bat` (Windows)

**Production method:** Use Docker or systemd service

**Server URL:** http://155.138.136.208:8800

**Credentials:** darkepwn / dh2akf5ksdai44ad0y
