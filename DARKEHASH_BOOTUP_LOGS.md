# DarkeHash Bootup Logs Feature

The DarkeHash plugin now automatically transmits bootup/startup logs when the device first connects to the internet after starting up.

## What Changed

### Plugin Enhancements

1. **Bootup Detection**
   - Tracks system uptime to determine when device booted
   - Checks database to see if bootup logs already sent this session
   - Only sends bootup logs once per boot

2. **First Internet Connection Priority**
   - On first internet connection after boot, sends bootup logs BEFORE other uploads
   - Captures startup logs including plugin initialization messages
   - Helps diagnose boot issues and plugin loading problems

3. **Upload Type Tracking**
   - Database now tracks upload types: 'bootup' or 'regular'
   - Server receives upload_type in JSON payload
   - Logs distinguish between bootup and regular uploads

### Technical Details

**New Database Field:**
```sql
CREATE TABLE IF NOT EXISTS status_uploads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uploaded_at TIMESTAMP,
    upload_type TEXT DEFAULT 'regular'  -- NEW FIELD
)
```

**Upload Flow:**
```
1. Pwnagotchi boots up
2. Plugin loads, checks if bootup logs sent this session
3. First internet connection detected
   ↓
4. Send bootup logs (if not already sent)
   - Includes startup messages
   - Marked as upload_type='bootup'
   - Logged: "DARKEHASH: Sending bootup logs..."
   ↓
5. Upload pending handshakes
   ↓
6. Send regular status/logs
   - Marked as upload_type='regular'
```

### Log Examples

**On bootup with internet:**
```
[INFO] DARKEHASH: Plugin loaded and ready
[DEBUG] DARKEHASH: Bootup logs need to be sent
[INFO] DARKEHASH: Sending bootup logs...
[INFO] DARKEHASH: Bootup logs uploaded successfully
```

**On subsequent internet connections:**
```
[DEBUG] DARKEHASH: Bootup logs already sent this session
[INFO] DARKEHASH: Found 2 handshake(s) to upload
[INFO] DARKEHASH: Status and logs uploaded successfully
```

**After reboot:**
```
[INFO] DARKEHASH: Plugin loaded and ready
[DEBUG] DARKEHASH: Bootup logs need to be sent
[INFO] DARKEHASH: Sending bootup logs...
[INFO] DARKEHASH: Bootup logs uploaded successfully
```

## Server Side

The server receives bootup logs with additional metadata:

```json
{
  "device_name": "pwny-01",
  "timestamp": "2025-01-15T10:30:00",
  "upload_type": "bootup",
  "log_data": "...startup logs here...",
  "system_info": {
    "uptime": 120,
    "version": "2.8.9",
    "handshakes_uploaded": 0,
    "handshakes_pending": 0
  }
}
```

The `upload_type` field distinguishes bootup logs from regular status updates.

## Benefits

### 1. Boot Diagnostics
- Capture startup issues and errors
- See exactly what happens during boot
- Identify plugin loading problems

### 2. Device Monitoring
- Know when devices restart
- Track uptime patterns
- Detect unexpected reboots

### 3. Historical Data
- Database tracks all bootup events
- Query when device was last rebooted
- Analyze boot frequency

### 4. Troubleshooting
- Debug plugin initialization issues
- See configuration loading errors
- Capture first-run problems

## Usage

No configuration changes needed! The feature works automatically.

**Optional: Query bootup uploads on Pwnagotchi:**
```bash
sqlite3 /home/pi/.darkehash_db \
  "SELECT uploaded_at, upload_type FROM status_uploads WHERE upload_type = 'bootup' ORDER BY uploaded_at DESC LIMIT 10;"
```

**Optional: Query bootup uploads on server:**
```bash
docker-compose exec darkehash-server sqlite3 /app/data/darkehash.db \
  "SELECT device_name, uploaded_at, substr(system_info, 1, 50) FROM status_logs WHERE system_info LIKE '%bootup%' ORDER BY uploaded_at DESC LIMIT 10;"
```

Or via API:
```bash
curl -u darkepwn:dh2akf5ksdai44ad0y http://155.138.136.208:8800/api/stats
```

## Implementation Notes

### Code Changes

**1. New instance variable:**
```python
self.bootup_logs_sent = False  # Track if bootup logs sent this session
```

**2. New method `_check_bootup_status()`:**
- Reads `/proc/uptime` to get boot time
- Queries database for last bootup upload
- Sets `bootup_logs_sent` flag appropriately

**3. Modified `on_internet_available()`:**
- Checks `bootup_logs_sent` flag
- Sends bootup logs if not already sent
- Sets flag to prevent duplicate sends

**4. Modified `_upload_status()`:**
- Accepts `upload_type` parameter
- Adds `upload_type` to JSON payload
- Records `upload_type` in database
- Logs differentiate bootup vs regular

### Backward Compatibility

✅ Fully backward compatible:
- Existing database automatically upgraded (new field has default value)
- Existing server code handles new field gracefully
- Plugin works same way if bootup detection fails (sends as regular)

## Testing

### Test bootup logs are sent:

1. **Reboot Pwnagotchi:**
   ```bash
   sudo reboot
   ```

2. **Watch logs after boot:**
   ```bash
   tail -f /var/log/pwnagotchi.log | grep DARKEHASH
   ```

3. **Look for:**
   ```
   [INFO] DARKEHASH: Sending bootup logs...
   [INFO] DARKEHASH: Bootup logs uploaded successfully
   ```

4. **Check server received them:**
   ```bash
   curl -u darkepwn:dh2akf5ksdai44ad0y http://155.138.136.208:8800/api/stats
   ```

5. **Check database:**
   ```bash
   sqlite3 /home/pi/.darkehash_db \
     "SELECT * FROM status_uploads WHERE upload_type = 'bootup' ORDER BY uploaded_at DESC LIMIT 1;"
   ```

### Test subsequent connections don't resend:

1. **Disconnect from internet**
2. **Reconnect**
3. **Check logs:**
   ```
   [DEBUG] DARKEHASH: Bootup logs already sent this session
   ```

No duplicate bootup upload should occur.

## Troubleshooting

### Bootup logs not sent

**Check if already sent:**
```bash
sqlite3 /home/pi/.darkehash_db \
  "SELECT uploaded_at FROM status_uploads WHERE upload_type = 'bootup' ORDER BY uploaded_at DESC LIMIT 1;"
```

**Check system uptime:**
```bash
cat /proc/uptime
```

**Force resend (for testing):**
```bash
# Delete bootup log record
sqlite3 /home/pi/.darkehash_db \
  "DELETE FROM status_uploads WHERE upload_type = 'bootup';"

# Restart Pwnagotchi
sudo systemctl restart pwnagotchi
```

### Bootup logs sent multiple times

This shouldn't happen, but if it does:
- Check system time is correct
- Check `/proc/uptime` is readable
- Check database permissions
- Review logs for errors

## Future Enhancements

Possible future additions:
- Upload system dmesg on bootup
- Include hardware info (CPU, memory, disk)
- Track boot duration
- Alert on crash reboots (short uptime)
- Boot reason detection (crash vs clean restart)

## Summary

The DarkeHash plugin now intelligently captures and transmits bootup logs on first internet connection, providing valuable diagnostic data and device monitoring capabilities without any configuration changes required.
