# DarkeHash Deployment Configuration

## Server Details

**IP Address:** 155.138.136.208
**Port:** 8800
**Full URL:** http://155.138.136.208:8800

## Credentials

**Username:** darkepwn
**Password:** dh2akf5ksdai44ad0y

## Quick Deployment

### 1. Deploy Server

```bash
cd darkehash-server
docker-compose up -d
docker-compose logs -f
```

The `.env` file is already configured with production values.

### 2. Test Server

```bash
# Health check (no auth)
curl http://localhost:8800/health

# Stats endpoint (with auth)
curl -u darkepwn:dh2akf5ksdai44ad0y http://localhost:8800/api/stats

# Or run full test suite
python3 test_upload.py
```

### 3. Configure Firewall

```bash
# UFW
sudo ufw allow 8800/tcp
sudo ufw status

# iptables
sudo iptables -A INPUT -p tcp --dport 8800 -j ACCEPT
sudo iptables-save
```

### 4. Verify External Access

```bash
# From another machine
curl http://155.138.136.208:8800/health
```

## Pwnagotchi Configuration

Add this to `/etc/pwnagotchi/config.toml` on each device:

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

Then restart:
```bash
sudo systemctl restart pwnagotchi
```

## Pre-configured Files

The following files are already configured with production values:

- `darkehash-server/.env` - Server environment variables
- `darkehash-server/.env.example` - Template with production defaults
- `darkehash-server/docker-compose.yml` - Port mapping to 8800
- `darkehash-server/test_upload.py` - Test script with credentials
- `darkehash-plugin-config.toml` - Copy/paste Pwnagotchi config

## Verification Checklist

- [ ] Server running: `docker-compose ps`
- [ ] Health check: `curl http://localhost:8800/health`
- [ ] External access: `curl http://155.138.136.208:8800/health`
- [ ] Firewall rule added for port 8800
- [ ] Pwnagotchi config updated
- [ ] Pwnagotchi restarted
- [ ] First handshake uploaded successfully

## Monitoring

### Check Server Uploads

```bash
# View recent uploads
docker-compose exec darkehash-server sqlite3 /app/data/darkehash.db \
  "SELECT device_name, filename, uploaded_at FROM handshakes ORDER BY uploaded_at DESC LIMIT 10;"

# Count by device
docker-compose exec darkehash-server sqlite3 /app/data/darkehash.db \
  "SELECT device_name, COUNT(*) FROM handshakes GROUP BY device_name;"

# Get statistics
curl -u darkepwn:dh2akf5ksdai44ad0y http://155.138.136.208:8800/api/stats
```

### Check Pwnagotchi Status

```bash
# SSH to Pwnagotchi
ssh pi@<pwnagotchi-ip>

# View plugin logs
tail -f /var/log/pwnagotchi.log | grep DARKEHASH

# Check database
sqlite3 /home/pi/.darkehash_db "SELECT COUNT(*), status FROM handshakes GROUP BY status;"
```

## File Locations

### Server
- Database: `darkehash-server/data/darkehash.db`
- Uploads: `darkehash-server/uploads/handshakes/`
- Logs: `darkehash-server/uploads/logs/`
- Config: `darkehash-server/.env`

### Pwnagotchi
- Plugin: `pwnagotchi/plugins/default/darkehash.py`
- Config: `/etc/pwnagotchi/config.toml`
- Database: `/home/pi/.darkehash_db`
- Logs: `/var/log/pwnagotchi.log`

## Troubleshooting

### Server not accessible externally

```bash
# Check if port is listening
sudo netstat -tuln | grep 8800

# Check firewall
sudo ufw status
sudo iptables -L -n | grep 8800

# Check docker
docker-compose ps
docker-compose logs
```

### Pwnagotchi not uploading

```bash
# Test connectivity from Pwnagotchi
curl -u darkepwn:dh2akf5ksdai44ad0y http://155.138.136.208:8800/health

# Check plugin is loaded
tail -f /var/log/pwnagotchi.log | grep -i darkehash

# Check config
grep -A 10 "\[main.plugins.darkehash\]" /etc/pwnagotchi/config.toml
```

## Security Notes

1. **Password is in plain text** in the `.env` file and config files
2. **HTTP only** - Consider setting up HTTPS with nginx/Caddy for production
3. **Firewall** - Only allow access from trusted IPs if possible
4. **Backups** - Regularly backup the database and uploads directory

## Optional: HTTPS Setup

For secure deployment, set up nginx with Let's Encrypt:

```bash
sudo apt-get install nginx certbot python3-certbot-nginx

# Create nginx config for darkehash.yourdomain.com
# Point it to http://localhost:8800
# Get SSL certificate with certbot

# Then update Pwnagotchi config to use:
# server_url = "https://darkehash.yourdomain.com"
```

See `DARKEHASH_QUICKSTART.md` for detailed nginx configuration.

## Support

For issues:
1. Check server logs: `docker-compose logs -f`
2. Check Pwnagotchi logs: `tail -f /var/log/pwnagotchi.log | grep DARKEHASH`
3. Test connectivity: `curl -u darkepwn:dh2akf5ksdai44ad0y http://155.138.136.208:8800/health`
4. Review documentation: `DARKEHASH_PLUGIN.md`, `darkehash-server/README.md`
