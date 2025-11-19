# DarkeHash Plugin for Pwnagotchi

The DarkeHash plugin automatically uploads captured handshakes and device status/logs to a custom server endpoint. This plugin is designed for users who want to centrally collect and manage handshakes from multiple Pwnagotchi devices.

## Features

- **Automatic Upload**: Uploads captured handshakes when internet is available
- **Bootup Logs**: Automatically sends startup/bootup logs on first internet connection
- **Status Reporting**: Sends device logs and statistics to server
- **Retry Logic**: Automatically retries failed uploads (configurable)
- **Whitelist Support**: Respects Pwnagotchi whitelist configuration
- **SQLite Tracking**: Tracks upload status in local database
- **UI Integration**: Optional display element showing upload statistics
- **Failure Handling**: Gracefully handles network errors and file issues

## Installation

The plugin is included in this fork by default at:
```
pwnagotchi/plugins/default/darkehash.py
```

If you're using a different Pwnagotchi installation, copy the plugin to:
```
/usr/local/share/pwnagotchi/custom-plugins/darkehash.py
```

## Configuration

Add the following to `/etc/pwnagotchi/config.toml`:

```toml
[main.plugins.darkehash]
# Enable the plugin
enabled = true

# Server configuration (required)
server_url = "http://your-server.com:5000"
username = "pwnagotchi"
password = "your_secure_password"

# Upload settings
upload_logs = true          # Upload device logs with status
log_lines = 200             # Number of log lines to include
max_retries = 3             # Maximum retry attempts for failed uploads

# UI settings
show_status = false         # Show upload stats on display (optional)
```

### Configuration Options

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `enabled` | bool | Yes | `false` | Enable the plugin |
| `server_url` | string | Yes | - | Base URL of DarkeHash server |
| `username` | string | Yes | - | Basic auth username |
| `password` | string | Yes | - | Basic auth password |
| `upload_logs` | bool | No | `true` | Upload logs with status |
| `log_lines` | int | No | `200` | Number of log lines to upload |
| `max_retries` | int | No | `3` | Max retry attempts for failed uploads |
| `show_status` | bool | No | `false` | Display upload stats on screen |

## How It Works

### 1. Plugin Initialization
When the plugin loads, it:
- Validates required configuration (server_url, username, password)
- Checks if bootup logs have been sent since last reboot
- Prepares to send startup logs on first internet connection

### 2. Bootup Logs (First Internet Connection)
On the **first** internet connection after bootup:
- Automatically uploads recent log entries (includes startup logs)
- Marks upload as "bootup" type in database
- Captures initial system state and statistics
- Only happens once per boot session

### 3. Handshake Capture
When a handshake is captured, the `on_handshake()` hook is triggered:
- Checks if network is whitelisted (skips if whitelisted)
- Adds handshake to local SQLite database with `PENDING` status
- Waits for internet connectivity

### 4. Internet Detection & Uploads
When internet becomes available, the `on_internet_available()` hook is triggered:
- **First**: Sends bootup logs if not already sent this session
- **Second**: Queries database for pending handshakes
- Uploads each handshake with metadata (SSID, BSSID, filename)
- Updates database status to `UPLOADED` on success
- Increments retry counter on failure
- Marks as `FAILED` after max retries exceeded

### 5. Regular Status Reporting
If `upload_logs` is enabled (on every internet connection):
- Reads recent log entries from Pwnagotchi log file
- Collects system information (uptime, handshake counts)
- Uploads to server as JSON payload
- Logs are also saved as individual files on server (if configured)

### 6. UI Display (Optional)
If `show_status` is enabled:
- Shows upload statistics on display: `DH: 45↑ 2⏳`
- Format: `{uploaded_count}↑ {pending_count}⏳`
- Updates on each UI refresh cycle

## Database

The plugin maintains a local SQLite database at `/home/pi/.darkehash_db` with:

### Tables

**handshakes**
- `path` (TEXT PRIMARY KEY): Handshake file path
- `status` (INTEGER): Upload status (0=PENDING, 1=UPLOADED, 2=FAILED)
- `uploaded_at` (TIMESTAMP): Upload timestamp
- `retry_count` (INTEGER): Number of retry attempts

**status_uploads**
- `id` (INTEGER PRIMARY KEY): Upload record ID
- `uploaded_at` (TIMESTAMP): Status upload timestamp
- `upload_type` (TEXT): Type of upload ('bootup' or 'regular')

## Logs

Plugin logs are prefixed with `DARKEHASH:` in the main Pwnagotchi log:

```bash
# View plugin logs
tail -f /var/log/pwnagotchi.log | grep DARKEHASH

# Example output
[INFO] DARKEHASH: Plugin loaded and ready
[DEBUG] DARKEHASH: Bootup logs need to be sent
[INFO] DARKEHASH: Sending bootup logs...
[INFO] DARKEHASH: Bootup logs uploaded successfully
[INFO] DARKEHASH: Queued handshake /home/pi/handshakes/Network_AA-BB-CC.pcap for upload
[INFO] DARKEHASH: Found 3 handshake(s) to upload
[INFO] DARKEHASH: Uploading /home/pi/handshakes/Network_AA-BB-CC.pcap...
[INFO] DARKEHASH: Successfully uploaded /home/pi/handshakes/Network_AA-BB-CC.pcap
[INFO] DARKEHASH: Status and logs uploaded successfully
```

## Troubleshooting

### Plugin Not Loading

**Check configuration:**
```bash
grep -A 10 "\[main.plugins.darkehash\]" /etc/pwnagotchi/config.toml
```

**Check Pwnagotchi logs:**
```bash
tail -f /var/log/pwnagotchi.log | grep -i darkehash
```

**Common issues:**
- Missing required options (`server_url`, `username`, `password`)
- Plugin not enabled (`enabled = true`)
- Syntax errors in TOML configuration

### Uploads Not Working

**Test server connectivity:**
```bash
# From Pwnagotchi
curl -u username:password http://your-server:5000/health
```

**Check database:**
```bash
sqlite3 /home/pi/.darkehash_db "SELECT * FROM handshakes WHERE status = 0;"
```

**Check for errors:**
```bash
journalctl -u pwnagotchi -f | grep DARKEHASH
```

**Common issues:**
- No internet connectivity
- Wrong server URL or credentials
- Firewall blocking connection
- Server not running

### Failed Uploads

**Check retry counts:**
```bash
sqlite3 /home/pi/.darkehash_db "SELECT path, retry_count, status FROM handshakes WHERE status = 2;"
```

**Reset failed uploads:**
```bash
sqlite3 /home/pi/.darkehash_db "UPDATE handshakes SET status = 0, retry_count = 0 WHERE status = 2;"
```

**View upload statistics:**
```bash
sqlite3 /home/pi/.darkehash_db << EOF
SELECT
    COUNT(*) as total,
    SUM(CASE WHEN status = 0 THEN 1 ELSE 0 END) as pending,
    SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) as uploaded,
    SUM(CASE WHEN status = 2 THEN 1 ELSE 0 END) as failed
FROM handshakes;
EOF
```

### Display Issues

If `show_status = true` but nothing appears:
- Check UI element position conflicts with other plugins
- Verify display size supports additional elements
- Try different position in plugin code (line 258-259)

## Security Considerations

1. **Use HTTPS**: Always use HTTPS URLs for server_url in production
2. **Strong Passwords**: Use strong, unique passwords for authentication
3. **Network Security**: Consider using VPN or secure tunnel for uploads
4. **Log Privacy**: Logs may contain sensitive information; secure your server
5. **Database Backup**: Backup the SQLite database regularly

## Performance

The plugin is designed to be lightweight:
- **Upload triggered only when internet available**
- **Non-blocking**: Uses threading and locks to prevent blocking main loop
- **Efficient database**: SQLite with WAL mode for better concurrency
- **Rate limiting**: Only uploads when new handshakes are available

## Integration with Other Plugins

DarkeHash works alongside other upload plugins:
- Can run with `wpa-sec`, `wigle`, etc.
- Each plugin maintains separate upload tracking
- Respects global whitelist configuration
- Uses standard plugin hooks and patterns

## Server Setup

For server setup instructions, see:
```
darkehash-server/README.md
```

Quick server start:
```bash
cd darkehash-server
cp .env.example .env
# Edit .env with your credentials
docker-compose up -d
```

## Example Configuration

### Minimal Configuration
```toml
[main.plugins.darkehash]
enabled = true
server_url = "http://192.168.1.100:5000"
username = "pwny"
password = "secure123"
```

### Full Configuration
```toml
[main.plugins.darkehash]
enabled = true
server_url = "https://darkehash.example.com"
username = "pwnagotchi-device-01"
password = "very_secure_password_here"
upload_logs = true
log_lines = 300
max_retries = 5
show_status = true
```

### Multiple Devices
Each device should have a unique username or use the same credentials:

**Device 1:**
```toml
[main.plugins.darkehash]
enabled = true
server_url = "https://darkehash.example.com"
username = "pwny-01"
password = "shared_password"
```

**Device 2:**
```toml
[main.plugins.darkehash]
enabled = true
server_url = "https://darkehash.example.com"
username = "pwny-02"
password = "shared_password"
```

The server will track uploads by device_name (from main.name config) automatically.

## Development

### Testing the Plugin

**1. Check plugin is loaded:**
```bash
curl http://localhost:8080/plugins
```

**2. Trigger manual upload (SSH into Pwnagotchi):**
```python
import sqlite3
# Add a test handshake
conn = sqlite3.connect('/home/pi/.darkehash_db')
conn.execute("INSERT OR REPLACE INTO handshakes (path, status, retry_count) VALUES ('/home/pi/handshakes/test.pcap', 0, 0)")
conn.commit()
conn.close()
# Wait for next internet check or restart pwnagotchi
```

**3. Monitor plugin execution:**
```bash
tail -f /var/log/pwnagotchi.log | grep -E "(DARKEHASH|internet)"
```

### Modifying the Plugin

The plugin source is at:
```
pwnagotchi/plugins/default/darkehash.py
```

After modifications:
```bash
# Restart Pwnagotchi to reload plugin
sudo systemctl restart pwnagotchi
```

## License

GPL3 - Same as Pwnagotchi project

## Credits

Based on the plugin architecture of Pwnagotchi by [@evilsocket](https://github.com/evilsocket) and inspired by the wpa-sec plugin by [@dadav](https://github.com/dadav).

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review server logs: `docker-compose logs`
3. Check Pwnagotchi logs: `tail -f /var/log/pwnagotchi.log`
4. Test server connectivity from Pwnagotchi device
5. Verify configuration syntax is valid TOML
