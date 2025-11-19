# DarkeHash Quick Start Guide

Complete guide to setting up DarkeHash plugin and server for Pwnagotchi handshake uploads.

## Overview

DarkeHash consists of two components:
1. **Pwnagotchi Plugin** - Runs on your Pwnagotchi device, uploads handshakes
2. **Flask Server** - Receives uploads, stores files and metadata

```
┌─────────────────┐
│  Pwnagotchi 1   │──┐
│  (darkehash.py) │  │
└─────────────────┘  │
                     │    ┌──────────────────┐
┌─────────────────┐  │    │  DarkeHash       │
│  Pwnagotchi 2   │──┼───▶│  Server          │
│  (darkehash.py) │  │    │  (Flask+Docker)  │
└─────────────────┘  │    └──────────────────┘
                     │           │
┌─────────────────┐  │           │
│  Pwnagotchi N   │──┘           ▼
│  (darkehash.py) │         ┌─────────┐
└─────────────────┘         │Database │
                            │+ Files  │
                            └─────────┘
```

## Part 1: Server Setup (15 minutes)

### Step 1: Prepare Server Environment

You need a server (VPS, home server, or cloud instance) with:
- Docker and Docker Compose installed
- Open port (default: 5000)
- Public IP or domain name (for remote access)

**Install Docker (if needed):**
```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt-get install docker-compose-plugin
```

### Step 2: Deploy DarkeHash Server

```bash
# Clone or copy the darkehash-server directory to your server
cd darkehash-server

# Create environment file
cp .env.example .env

# Edit with your credentials
nano .env
```

**Edit `.env` file:**
```env
PORT=8800
AUTH_USERNAME=darkepwn
AUTH_PASSWORD=dh2akf5ksdai44ad0y
MAX_FILE_SIZE=10485760
SAVE_LOGS_TO_FILE=true
DEBUG=false
```

**Start the server:**
```bash
# Build and start
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

### Step 3: Test Server

```bash
# Test health endpoint (no auth)
curl http://localhost:8800/health

# Should return:
# {"status":"healthy","timestamp":"2025-01-15T10:30:00","version":"1.0.0"}

# Test with authentication
curl -u darkepwn:dh2akf5ksdai44ad0y http://localhost:8800/api/stats

# Should return stats JSON
```

**Run full test suite:**
```bash
# Edit test_upload.py with your credentials
nano test_upload.py

# Run tests
python3 test_upload.py
```

### Step 4: Configure Firewall (if needed)

```bash
# UFW (Ubuntu)
sudo ufw allow 8800/tcp

# iptables
sudo iptables -A INPUT -p tcp --dport 8800 -j ACCEPT
```

### Step 5: Optional - Setup HTTPS with nginx

**Install nginx:**
```bash
sudo apt-get install nginx certbot python3-certbot-nginx
```

**Create nginx config:**
```bash
sudo nano /etc/nginx/sites-available/darkehash
```

```nginx
server {
    listen 80;
    server_name darkehash.yourdomain.com;

    location / {
        proxy_pass http://localhost:8800;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
    }
}
```

**Enable and get SSL:**
```bash
sudo ln -s /etc/nginx/sites-available/darkehash /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d darkehash.yourdomain.com
```

---

## Part 2: Pwnagotchi Plugin Setup (10 minutes)

### Step 1: Plugin Installation

The plugin is already included if you're using this fork:
```
pwnagotchi/plugins/default/darkehash.py
```

If not, copy it to your Pwnagotchi:
```bash
# From your computer
scp darkehash.py pi@10.0.0.2:/usr/local/share/pwnagotchi/custom-plugins/

# Or SSH to Pwnagotchi and download
ssh pi@10.0.0.2
wget -O /usr/local/share/pwnagotchi/custom-plugins/darkehash.py \
    https://raw.githubusercontent.com/YOUR_REPO/darkehash.py
```

### Step 2: Configure Plugin

SSH into your Pwnagotchi:
```bash
ssh pi@10.0.0.2
```

Edit configuration:
```bash
sudo nano /etc/pwnagotchi/config.toml
```

Add plugin configuration:
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

**Server is configured at:** `155.138.136.208:8800`

If using a different server, replace with:
- Your server's public IP: `http://1.2.3.4:8800`
- Your domain: `https://darkehash.yourdomain.com`
- Local network IP: `http://192.168.1.100:8800`

### Step 3: Restart Pwnagotchi

```bash
sudo systemctl restart pwnagotchi
```

### Step 4: Verify Plugin is Working

**Check logs:**
```bash
# Watch for plugin loading
tail -f /var/log/pwnagotchi.log | grep DARKEHASH

# Should see:
# [INFO] DARKEHASH: Plugin loaded and ready
```

**Test upload manually:**
```bash
# Check database
sqlite3 /home/pi/.darkehash_db "SELECT * FROM handshakes;"

# Check internet detection
tail -f /var/log/pwnagotchi.log | grep -E "(DARKEHASH|internet)"
```

---

## Part 3: Verification (5 minutes)

### Check Server Received Uploads

**On server:**
```bash
# Check database
docker-compose exec darkehash-server sqlite3 /app/data/darkehash.db \
    "SELECT device_name, filename, uploaded_at FROM handshakes ORDER BY uploaded_at DESC LIMIT 5;"

# Check files
ls -lh uploads/handshakes/

# View stats
curl -u darkepwn:dh2akf5ksdai44ad0y http://localhost:8800/api/stats
```

### Check Pwnagotchi Status

**On Pwnagotchi:**
```bash
# View upload statistics
sqlite3 /home/pi/.darkehash_db << EOF
SELECT
    COUNT(*) as total,
    SUM(CASE WHEN status = 0 THEN 1 ELSE 0 END) as pending,
    SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) as uploaded,
    SUM(CASE WHEN status = 2 THEN 1 ELSE 0 END) as failed
FROM handshakes;
EOF
```

---

## Troubleshooting

### Server Issues

**Container not starting:**
```bash
docker-compose logs
docker-compose ps
docker-compose restart
```

**Can't connect from outside:**
- Check firewall rules
- Verify port is open: `netstat -tuln | grep 8800`
- Test from another machine: `curl http://155.138.136.208:8800/health`

### Plugin Issues

**Plugin not loading:**
```bash
# Check config syntax
pwnagotchi --print-config | grep -A 10 darkehash

# Check for errors
journalctl -u pwnagotchi -n 100 | grep -i error
```

**Not uploading:**
```bash
# Test connectivity from Pwnagotchi
curl -u darkepwn:dh2akf5ksdai44ad0y http://155.138.136.208:8800/health

# Check internet connectivity
ping -c 3 8.8.8.8

# Check pending uploads
sqlite3 /home/pi/.darkehash_db "SELECT COUNT(*) FROM handshakes WHERE status = 0;"
```

**Authentication errors:**
- Verify username/password match between plugin config and server .env
- Check for special characters in password (may need escaping)

---

## Configuration Examples

### Example 1: Single Device, Local Network

**Server:** Running on `192.168.1.50:5000`

**Pwnagotchi config.toml:**
```toml
[main.plugins.darkehash]
enabled = true
server_url = "http://192.168.1.50:5000"
username = "pwny"
password = "homelab123"
```

### Example 2: Multiple Devices, Public Server

**Server:** `https://darkehash.example.com` (with nginx + SSL)

**Device 1 config.toml:**
```toml
[main]
name = "pwny-field"

[main.plugins.darkehash]
enabled = true
server_url = "https://darkehash.example.com"
username = "pwnagotchi"
password = "secure_shared_password"
```

**Device 2 config.toml:**
```toml
[main]
name = "pwny-mobile"

[main.plugins.darkehash]
enabled = true
server_url = "https://darkehash.example.com"
username = "pwnagotchi"
password = "secure_shared_password"
```

Server will track by device name automatically.

### Example 3: VPN Connection

**Server:** Behind VPN at `10.8.0.1:5000`

**Pwnagotchi config.toml:**
```toml
[main.plugins.darkehash]
enabled = true
server_url = "http://10.8.0.1:5000"
username = "pwny"
password = "vpn_secured"
```

Requires Pwnagotchi to connect to VPN when internet available.

---

## Maintenance

### Daily Checks

```bash
# Server: Check for new uploads
curl -u user:pass http://localhost:5000/api/stats | jq '.total_handshakes'

# View recent uploads
docker-compose exec darkehash-server sqlite3 /app/data/darkehash.db \
    "SELECT COUNT(*), DATE(uploaded_at) FROM handshakes GROUP BY DATE(uploaded_at);"
```

### Weekly Backups

```bash
# Backup database
cp data/darkehash.db data/darkehash.db.backup.$(date +%Y%m%d)

# Backup uploads
tar -czf uploads_backup_$(date +%Y%m%d).tar.gz uploads/
```

### Monthly Cleanup

```bash
# Remove old log files (older than 30 days)
find uploads/logs -name "*.json" -mtime +30 -delete

# Vacuum database
docker-compose exec darkehash-server sqlite3 /app/data/darkehash.db "VACUUM;"
```

---

## Next Steps

1. **Monitor uploads**: Check server regularly for new handshakes
2. **Add more devices**: Repeat Part 2 for additional Pwnagotchis
3. **Secure server**: Use HTTPS, strong passwords, firewall rules
4. **Automate backups**: Set up cron jobs for database backups
5. **Process handshakes**: Use tools like `hashcat` or `aircrack-ng` on uploaded files

---

## File Locations

### Server
- Docker compose: `darkehash-server/docker-compose.yml`
- Database: `darkehash-server/data/darkehash.db`
- Handshakes: `darkehash-server/uploads/handshakes/`
- Logs: `darkehash-server/uploads/logs/`

### Pwnagotchi
- Plugin: `pwnagotchi/plugins/default/darkehash.py`
- Config: `/etc/pwnagotchi/config.toml`
- Database: `/home/pi/.darkehash_db`
- Handshakes: `/home/pi/handshakes/` (or configured path)
- Logs: `/var/log/pwnagotchi.log`

---

## Support & Documentation

- **Plugin Documentation**: `DARKEHASH_PLUGIN.md`
- **Server Documentation**: `darkehash-server/README.md`
- **Test Script**: `darkehash-server/test_upload.py`

---

## Summary Checklist

### Server Setup
- [ ] Docker and Docker Compose installed
- [ ] `.env` file configured with credentials
- [ ] Server started: `docker-compose up -d`
- [ ] Health check passes: `curl http://localhost:8800/health`
- [ ] Firewall configured (port 8800 open)
- [ ] Optional: HTTPS configured with nginx

### Plugin Setup
- [ ] Plugin file in place (darkehash.py)
- [ ] Config.toml updated with server URL and credentials
- [ ] Pwnagotchi restarted
- [ ] Plugin loaded: logs show "DARKEHASH: Plugin loaded and ready"
- [ ] Test handshake captured and uploaded

### Verification
- [ ] Server shows uploaded handshakes: `/api/stats`
- [ ] Files stored in `uploads/handshakes/`
- [ ] Database contains entries
- [ ] Pwnagotchi logs show successful uploads

---

**You're all set! Your Pwnagotchi will now automatically upload handshakes to your custom server.**
