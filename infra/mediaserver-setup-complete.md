# Media Server - Pwnagotchi Cracking Setup Complete

**Server Hostname**: mediaserver
**Setup Date**: 2024-11-08
**Status**: ✓ Operational

---

## Hardware Configuration

### CPU
- **Model**: Intel Core i5-2500 @ 3.30GHz
- **Architecture**: Sandy Bridge (2nd Gen, 2011)
- **Cores**: 4 physical cores, 4 threads (no hyperthreading)
- **Features**:
  - ✓ AES-NI (hardware AES acceleration)
  - ✓ AVX (first generation)
  - ✓ SSE

### GPU
- **Model**: NVIDIA GeForce GTX 960 4GB
- **Architecture**: Maxwell GM206
- **VRAM**: 4096 MB
- **CUDA Cores**: 1024
- **Memory Bus**: 128-bit
- **TDP**: 120W (limit set to 130W)
- **Driver**: NVIDIA 535.274.02
- **CUDA Version**: 12.2
- **PCIe Slot**: PCIe 2.0 x16

**Performance Benchmarks**:
- WPA2 (22000): **120,800 H/s**
- MD5: **3,144 MH/s**
- Status: ✓ Working correctly for hardware limitations

### Memory
- **Total**: 32 GB DDR3
- **Configuration**: 4x 8GB modules
- **Speed**: 1600 MT/s
- **Manufacturer**: Corsair
- **Type**: DDR3 (non-ECC)

### Storage
- **Primary**: 931.5 GB HDD (SATA)
- **Used**: 52 GB (6%)
- **Available**: 818 GB
- **Filesystem**: ext4
- **Mounted**: /dev/sda2 on /

### Network
- **Interface**: enp6s1
- **IP Address**: 10.0.1.170/22
- **Type**: Ethernet (wired)
- **Status**: UP

### Operating System
- **Distribution**: Ubuntu 24.04.2 LTS
- **Kernel**: 6.14.0-27-generic
- **Architecture**: x86_64
- **Desktop**: GNOME (headless mode - text-only)
- **System Type**: Desktop/Server

---

## Software Installation

### NVIDIA Drivers & CUDA
```bash
# Installed drivers
nvidia-driver-535
nvidia-utils-535

# CUDA Toolkit
nvidia-cuda-toolkit (CUDA 12.2)

# Verification
nvidia-smi          # Shows GPU stats
nvcc --version      # Shows CUDA compiler
```

### Hashcat & Tools
```bash
# Installed packages
hashcat (v6.2.6)
hcxtools
hcxdumptool
aircrack-ng
rsync

# Verification
hashcat --version
hashcat -I          # Shows GPU devices
hcxpcapngtool --version
```

---

## GPU Configuration

### Performance Settings
```bash
# Persistence mode enabled
nvidia-smi -pm 1

# Power limit set to maximum
nvidia-smi -pl 130

# Auto-starts on boot via systemd service
systemctl status nvidia-performance.service
```

### Persistence Service
**File**: `/etc/systemd/system/nvidia-performance.service`

```ini
[Unit]
Description=NVIDIA GPU Performance Mode
After=nvidia-persistenced.service

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -pl 130
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**Status**: ✓ Enabled and running

### GPU State Monitoring
```bash
# Check GPU status
nvidia-smi

# Expected output when idle:
# - Persistence-M: On
# - Perf: P8 (idle) or P2 (compute)
# - Power: 16W (idle) to 102W (full load)
# - Temp: 32-54°C under load
# - Memory: 1MB (idle) to 3552MB (full workload)
```

---

## Cracking Infrastructure

### Directory Structure
**Base Path**: `/home/media/pwnagotchi-cracking/`

```
pwnagotchi-cracking/
├── incoming/           # Place .pcap files here (auto-synced from Pwnagotchi)
├── processing/         # Files currently being processed
├── cracked/           # Successfully cracked handshakes
│   ├── *.txt          # Password results
│   └── *.info         # Detailed crack information
├── failed/            # Handshakes that couldn't be cracked
├── wordlists/         # Password dictionaries
│   ├── rockyou.txt    # 14M passwords (~133 MB)
│   └── wifi-common.txt # WiFi-specific passwords
├── hashes/            # Converted hash files (22000 format)
├── logs/              # Processing logs
│   └── cracking-YYYYMMDD.log
├── process-handshakes.sh  # Main processing script
└── status.sh          # Status monitoring script
```

### Automation

**Cron Job**: Processes handshakes every 15 minutes
```bash
# View cron schedule
crontab -l

# Expected output:
*/15 * * * * /home/media/pwnagotchi-cracking/process-handshakes.sh
```

**Manual Processing**:
```bash
# Process all files in incoming/ immediately
~/pwnagotchi-cracking/process-handshakes.sh

# View status
~/pwnagotchi-cracking/status.sh
```

### Wordlist Configuration

**Priority Order** (defined in `process-handshakes.sh`):
1. `wifi-common.txt` - Quick common passwords (~20 entries)
2. `rockyou.txt` - Popular leaked passwords (14M entries)

**Adding More Wordlists**:
```bash
cd ~/pwnagotchi-cracking/wordlists/

# Download additional wordlists
wget https://example.com/wordlist.txt

# Edit process-handshakes.sh to add to priority list
nano ~/pwnagotchi-cracking/process-handshakes.sh
# Add to WORDLISTS_PRIORITY array
```

---

## Performance & Capacity

### Current Cracking Speed
- **WPA2 Speed**: 120,800 H/s (verified via benchmark)
- **GPU Utilization**: 100% during cracking
- **Power Draw**: 102W at full load

### Time Estimates

| Password List | Size | Estimated Time |
|---------------|------|----------------|
| wifi-common.txt | 20 | < 1 second |
| RockYou | 14 million | ~2 minutes |
| 100M passwords | 100 million | ~14 minutes |
| 1B passwords | 1 billion | ~2.3 hours |

### Storage Capacity

| Item | Size | Notes |
|------|------|-------|
| Total Available | 818 GB | Plenty for wordlists |
| RockYou wordlist | 133 MB | Installed |
| Average .pcap | 1-10 KB | Minimal |
| Large wordlist collections | 10-100 GB | Can accommodate |

### Daily Processing Capacity

At 120,800 H/s with 96 15-minute windows per day:
- **24 hours continuous**: ~10.4 billion password attempts
- **Realistic daily usage**: Depends on handshake volume from Pwnagotchi

---

## Integration with Pwnagotchi

### Transfer Methods

**Method 1: Manual Transfer (Current)**
```bash
# On Pwnagotchi
scp /home/pi/handshakes/*.pcap media@10.0.1.170:~/pwnagotchi-cracking/incoming/

# On server, process manually
~/pwnagotchi-cracking/process-handshakes.sh
```

**Method 2: Automated Sync (Recommended)**

On Pwnagotchi, create: `/usr/local/bin/sync-handshakes`
```bash
#!/bin/bash
SERVER_USER="media"
SERVER_IP="10.0.1.170"
SERVER_PATH="/home/media/pwnagotchi-cracking/incoming/"
LOCAL_PATH="/home/pi/handshakes/"

# Sync files modified in last 24 hours
find "$LOCAL_PATH" -name "*.pcap" -mtime -1 -exec rsync -avz --progress {} ${SERVER_USER}@${SERVER_IP}:${SERVER_PATH} \;

logger "Pwnagotchi handshakes synced to server"
```

Then add to Pwnagotchi crontab:
```bash
# Run hourly
0 * * * * /usr/local/bin/sync-handshakes
```

**Prerequisites**:
- SSH key authentication from Pwnagotchi → Media Server
- Network connectivity between devices

---

## Usage Instructions

### Basic Workflow

1. **Capture handshakes** with Pwnagotchi
2. **Transfer .pcap files** to `~/pwnagotchi-cracking/incoming/`
3. **Wait for automatic processing** (every 15 min) or run manually
4. **Check results** in `~/pwnagotchi-cracking/cracked/`

### Manual Operations

**Check Status**:
```bash
~/pwnagotchi-cracking/status.sh
```

**Process Immediately**:
```bash
~/pwnagotchi-cracking/process-handshakes.sh
```

**View Logs**:
```bash
# Today's log
tail -f ~/pwnagotchi-cracking/logs/cracking-$(date +%Y%m%d).log

# Recent activity
tail -50 ~/pwnagotchi-cracking/logs/cracking-*.log
```

**Check Successful Cracks**:
```bash
# List all cracked files
ls -lh ~/pwnagotchi-cracking/cracked/

# View specific crack details
cat ~/pwnagotchi-cracking/cracked/filename.info

# See just the passwords
cat ~/pwnagotchi-cracking/cracked/*.txt
```

### Testing with Sample Handshake

```bash
# Place test .pcap in incoming
cp test-handshake.pcap ~/pwnagotchi-cracking/incoming/

# Process manually (don't wait for cron)
~/pwnagotchi-cracking/process-handshakes.sh

# Check logs for results
tail ~/pwnagotchi-cracking/logs/cracking-$(date +%Y%m%d).log
```

---

## Monitoring & Maintenance

### GPU Health Monitoring

```bash
# Real-time GPU monitoring
watch -n 1 nvidia-smi

# Temperature check
nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader

# Power usage
nvidia-smi --query-gpu=power.draw --format=csv,noheader
```

**Normal Operating Ranges**:
- **Idle Temp**: 30-35°C
- **Load Temp**: 50-70°C
- **Max Safe**: 80°C (throttling begins)
- **Idle Power**: 15-20W
- **Load Power**: 80-110W

### System Resource Usage

```bash
# Overall system status
htop

# Disk space
df -h /home/media/pwnagotchi-cracking

# Check if hashcat is running
ps aux | grep hashcat

# View active processes on GPU
nvidia-smi pmon
```

### Log Management

Logs are automatically cleaned up after 30 days by the processing script.

Manual cleanup:
```bash
# Remove logs older than 30 days
find ~/pwnagotchi-cracking/logs/ -name "cracking-*.log" -mtime +30 -delete

# Archive old logs
tar czf logs-archive-$(date +%Y%m).tar.gz ~/pwnagotchi-cracking/logs/*.log
```

---

## Troubleshooting

### GPU Not Detected

**Symptoms**: hashcat shows "no CUDA-capable device"

**Fix**:
```bash
# Check driver status
nvidia-smi

# If failed, reinstall drivers
sudo ubuntu-drivers install
sudo reboot
```

### Low Performance

**Symptoms**: Speed below 100 kH/s for WPA2

**Checks**:
```bash
# Verify GPU is in performance mode
nvidia-smi | grep "P2\|P0"  # Should show P2 or P0, not P8

# Check power limit
nvidia-smi -q | grep "Power Limit"  # Should be 130W

# Re-enable performance mode
sudo nvidia-smi -pm 1
sudo nvidia-smi -pl 130
```

### Cron Not Running

**Symptoms**: Files sit in incoming/ without processing

**Fix**:
```bash
# Check cron service
sudo systemctl status cron

# Verify crontab entry
crontab -l

# Test script manually
~/pwnagotchi-cracking/process-handshakes.sh

# Check logs for errors
grep CRON /var/log/syslog | tail -20
```

### Out of Disk Space

**Symptoms**: Processing fails, "no space left" errors

**Fix**:
```bash
# Check space
df -h

# Clean up failed attempts (if acceptable)
rm ~/pwnagotchi-cracking/failed/*.pcap

# Clean old logs
find ~/pwnagotchi-cracking/logs/ -name "*.log" -mtime +7 -delete

# Move cracked files to backup
tar czf cracked-backup-$(date +%Y%m%d).tar.gz ~/pwnagotchi-cracking/cracked/
mv cracked-backup-*.tar.gz /backup/location/
rm ~/pwnagotchi-cracking/cracked/*
```

### GPU Overheating

**Symptoms**: Temperature > 80°C, throttling warnings

**Fix**:
```bash
# Check current temp
nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader

# Reduce workload profile in process-handshakes.sh
# Change: hashcat ... (no -w flag = default)
# Or use: -w 2 (medium workload)

# Check fan speed
nvidia-smi --query-gpu=fan.speed --format=csv,noheader

# Manually set fan speed (if needed)
nvidia-settings -a "[gpu:0]/GPUFanControlState=1"
nvidia-settings -a "[fan:0]/GPUTargetFanSpeed=70"
```

---

## Optimization Notes

### Current Limitations

1. **PCIe 2.0 Bottleneck**: Motherboard only supports PCIe 2.0, limiting GPU data transfer
2. **GTX 960 Performance**: This GPU achieves ~120k H/s for WPA2, which is normal for:
   - Maxwell architecture
   - 4GB memory variant
   - PCIe 2.0 interface
3. **No Display Timeout**: System is headless (text-only), so no display timeout issues

### Performance is Adequate For:
- ✓ Common password dictionaries (RockYou)
- ✓ Targeted wordlists (company names, patterns)
- ✓ WiFi audits with reasonable password policies
- ✓ Quick verification of weak passwords

### Performance is NOT Sufficient For:
- ✗ Large-scale brute force (billions of attempts)
- ✗ Complex password policies (12+ random characters)
- ✗ High-volume commercial cracking operations

### Upgrade Path (If Needed)

**Budget Option ($250-300)**:
- Used RTX 3060 12GB
- Expected: ~300k H/s (2.5x faster)
- Same PSU (550W+)

**Best Value ($500)**:
- RTX 4060 Ti 16GB
- Expected: ~500k H/s (4x faster)
- 16GB VRAM for huge wordlists
- Low power (160W)

**Check Before Upgrade**:
```bash
# Verify PSU wattage (check label inside case)
# Minimum recommendations:
# - RTX 3060: 550W
# - RTX 4060 Ti: 550W
# - RTX 4070: 650W
```

---

## Backup & Recovery

### Configuration Backup

**Files to backup**:
```bash
# Crontab
crontab -l > ~/pwnagotchi-cracking-crontab-backup.txt

# Processing script (if modified)
cp ~/pwnagotchi-cracking/process-handshakes.sh ~/backup/

# Status script (if modified)
cp ~/pwnagotchi-cracking/status.sh ~/backup/

# Systemd service
sudo cp /etc/systemd/system/nvidia-performance.service ~/backup/

# Wordlists (if custom)
tar czf wordlists-backup.tar.gz ~/pwnagotchi-cracking/wordlists/
```

### Restore After Reinstall

```bash
# Reinstall NVIDIA drivers
sudo ubuntu-drivers install
sudo reboot

# Reinstall hashcat and tools
sudo apt-get install hashcat hcxtools

# Restore systemd service
sudo cp ~/backup/nvidia-performance.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable nvidia-performance.service

# Restore directory structure
mkdir -p ~/pwnagotchi-cracking/{incoming,processing,cracked,failed,wordlists,hashes,logs}

# Restore scripts
cp ~/backup/*.sh ~/pwnagotchi-cracking/
chmod +x ~/pwnagotchi-cracking/*.sh

# Restore crontab
crontab ~/pwnagotchi-cracking-crontab-backup.txt

# Restore wordlists
tar xzf wordlists-backup.tar.gz -C ~/
```

---

## Security Considerations

### Access Control

**Current State**:
- System runs as user `media`
- Cracking infrastructure in `/home/media/pwnagotchi-cracking/`
- SSH access required for remote management

**Recommendations**:
1. Use SSH key authentication only (disable password auth)
2. Restrict SSH access to specific IPs if possible
3. Keep cracked passwords in encrypted storage
4. Regularly update system: `sudo apt-get update && sudo apt-get upgrade`

### Network Isolation

This server:
- Processes WiFi handshakes (authorized pentest data)
- Should NOT be exposed to internet directly
- Keep on isolated network segment if possible

### Data Retention

**Successful Cracks**:
- Store in `cracked/` directory
- Back up periodically
- Consider encryption for sensitive results

**Failed Attempts**:
- Move to `failed/` directory
- Optionally retry with larger wordlists
- Archive or delete after analysis

---

## Performance Verification Checklist

Run this after any changes to verify system is working:

```bash
# 1. Check GPU driver
nvidia-smi
# Expected: Shows GTX 960, driver 535.274.02

# 2. Check GPU performance mode
nvidia-smi | grep "Persistence-M"
# Expected: "On"

# 3. Verify hashcat can see GPU
hashcat -I
# Expected: Shows Device #1: NVIDIA GeForce GTX 960

# 4. Benchmark WPA2 speed
hashcat -b -m 22000 -w 3
# Expected: ~120,000 H/s

# 5. Check cron job
crontab -l
# Expected: Shows process-handshakes.sh every 15 min

# 6. Test status script
~/pwnagotchi-cracking/status.sh
# Expected: Shows directory status and hardware info

# 7. Check disk space
df -h /home/media/pwnagotchi-cracking
# Expected: >50GB free

# 8. Verify wordlists
ls -lh ~/pwnagotchi-cracking/wordlists/
# Expected: rockyou.txt (~133MB), wifi-common.txt
```

All checks should pass for confirmed working system.

---

## Quick Reference Commands

### Daily Operations
```bash
# Check what's happening
~/pwnagotchi-cracking/status.sh

# Process now (don't wait for cron)
~/pwnagotchi-cracking/process-handshakes.sh

# View recent logs
tail -f ~/pwnagotchi-cracking/logs/cracking-$(date +%Y%m%d).log

# Check GPU status
nvidia-smi

# List successful cracks
ls -lh ~/pwnagotchi-cracking/cracked/
```

### Troubleshooting
```bash
# Check if cron is running
sudo systemctl status cron

# Verify GPU performance
nvidia-smi | grep -E "Perf|Power|Temp"

# Test hashcat manually
cd ~/pwnagotchi-cracking/incoming
hashcat -m 22000 test.pcap ~/pwnagotchi-cracking/wordlists/rockyou.txt

# Check system resources
htop
df -h
```

### Maintenance
```bash
# Clean old logs (30+ days)
find ~/pwnagotchi-cracking/logs/ -name "*.log" -mtime +30 -delete

# Archive successful cracks
tar czf cracked-$(date +%Y%m%d).tar.gz ~/pwnagotchi-cracking/cracked/

# Update system
sudo apt-get update && sudo apt-get upgrade

# Reboot if needed
sudo reboot
```

---

## Summary

**Server**: mediaserver (10.0.1.170)
**GPU**: NVIDIA GTX 960 4GB
**Performance**: 120,800 H/s (WPA2)
**Status**: ✓ Fully operational
**Automation**: ✓ Cron every 15 minutes
**Capacity**: ~10 billion attempts per day

**Limitations**:
- Adequate for common passwords and targeted wordlists
- Not suitable for large-scale brute force operations
- Upgrade to RTX 4060 Ti recommended for 4x performance

**Next Steps**:
1. Set up Pwnagotchi → Server sync
2. Test with real handshake captures
3. Monitor performance over time
4. Consider GPU upgrade if needed

---

**Documentation Last Updated**: 2024-11-08
**Maintained By**: Setup automation via server_info_collector.sh
**Configuration Files**: See `/home/media/pwnagotchi-cracking/`
