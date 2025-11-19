#!/bin/bash
# Server Information Collector & Setup Assistant for Hashcat Optimization
# Collects system info and provides driver/software installation guidance
# Output saved to: <hostname>.txt

# Get hostname for output file
HOSTNAME=$(hostname)
OUTPUT_FILE="${HOSTNAME}.txt"

# Function to output to both screen and file
output() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

# Clear output file if exists
> "$OUTPUT_FILE"

output "========================================="
output "SYSTEM INFORMATION COLLECTOR"
output "Hostname: $HOSTNAME"
output "Collected: $(date '+%Y-%m-%d %H:%M:%S')"
output "========================================="
output ""

# Check if running with sudo for some commands
if [ "$EUID" -ne 0 ]; then
    output "NOTE: Some commands require sudo. Running without sudo may limit information."
    output "      Recommend running: sudo ./server_info_collector.sh"
    output ""
    SUDO_PREFIX=""
else
    SUDO_PREFIX="sudo"
fi

output "=== CPU INFORMATION ==="
output "Model:"
lscpu | grep "Model name" | tee -a "$OUTPUT_FILE"
output ""
output "Architecture:"
lscpu | grep "Architecture" | tee -a "$OUTPUT_FILE"
output ""
output "CPU Cores:"
lscpu | grep "^CPU(s):" | tee -a "$OUTPUT_FILE"
lscpu | grep "Thread(s) per core" | tee -a "$OUTPUT_FILE"
lscpu | grep "Core(s) per socket" | tee -a "$OUTPUT_FILE"
lscpu | grep "Socket(s):" | tee -a "$OUTPUT_FILE"
output ""
output "CPU Flags (important for hashcat):"
CPU_FLAGS=$(lscpu | grep "Flags")
if echo "$CPU_FLAGS" | grep -q "aes"; then
    output "✓ AES-NI: YES (hardware AES acceleration - 2-3x boost for WPA2)"
else
    output "✗ AES-NI: NO (slower WPA2 cracking)"
fi
if echo "$CPU_FLAGS" | grep -q "avx2"; then
    output "✓ AVX2: YES (advanced vector extensions)"
elif echo "$CPU_FLAGS" | grep -q "avx"; then
    output "✓ AVX: YES (basic vector extensions)"
else
    output "✗ AVX: NO"
fi
if echo "$CPU_FLAGS" | grep -q "sse"; then
    output "✓ SSE: YES"
fi
output ""

output "=== GPU INFORMATION ==="
output "Hardware Detection (lspci):"
GPU_LSPCI=$(lspci | grep -i "vga\|3d\|display")
echo "$GPU_LSPCI" | tee -a "$OUTPUT_FILE"
output ""

# Detect GPU vendor
NVIDIA_DETECTED=false
AMD_DETECTED=false
INTEL_DETECTED=false

if echo "$GPU_LSPCI" | grep -qi "nvidia"; then
    NVIDIA_DETECTED=true
fi
if echo "$GPU_LSPCI" | grep -qi "amd"; then
    AMD_DETECTED=true
fi
if echo "$GPU_LSPCI" | grep -qi "intel"; then
    INTEL_DETECTED=true
fi

# NVIDIA GPU Check
if [ "$NVIDIA_DETECTED" = true ]; then
    output "NVIDIA GPU Status:"
    if command -v nvidia-smi &> /dev/null; then
        output "✓ nvidia-smi: FOUND"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv 2>&1 | tee -a "$OUTPUT_FILE"
        output ""
        output "CUDA Version:"
        nvidia-smi | grep "CUDA Version" | tee -a "$OUTPUT_FILE"
        output ""
        output "✓ NVIDIA drivers: INSTALLED AND WORKING"
        output ""

        # Get GPU model for performance estimate
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        output "Detected GPU: $GPU_MODEL"

        # Estimate performance based on common models
        case "$GPU_MODEL" in
            *"4090"*)
                output "Estimated WPA2 speed: ~1,200,000 H/s"
                ;;
            *"4080"*)
                output "Estimated WPA2 speed: ~900,000 H/s"
                ;;
            *"4070"*)
                output "Estimated WPA2 speed: ~600,000 H/s"
                ;;
            *"4060 Ti"*)
                output "Estimated WPA2 speed: ~500,000 H/s"
                ;;
            *"4060"*)
                output "Estimated WPA2 speed: ~400,000 H/s"
                ;;
            *"3090"*)
                output "Estimated WPA2 speed: ~800,000 H/s"
                ;;
            *"3080"*)
                output "Estimated WPA2 speed: ~700,000 H/s"
                ;;
            *"3070"*)
                output "Estimated WPA2 speed: ~500,000 H/s"
                ;;
            *"3060"*)
                output "Estimated WPA2 speed: ~300,000 H/s"
                ;;
            *"2080 Ti"*)
                output "Estimated WPA2 speed: ~500,000 H/s"
                ;;
            *"1660"*)
                output "Estimated WPA2 speed: ~150,000 H/s"
                ;;
            *"960"*)
                output "Estimated WPA2 speed: ~175,000 H/s"
                ;;
            *"1050"*)
                output "Estimated WPA2 speed: ~100,000 H/s"
                ;;
            *)
                output "Estimated WPA2 speed: Unknown model - run benchmark"
                ;;
        esac
    else
        output "✗ nvidia-smi: NOT FOUND"
        output "✗ NVIDIA drivers: NOT INSTALLED OR BROKEN"
        output ""
        output ">>> ACTION REQUIRED: Install NVIDIA drivers <<<"
        output ""
        output "Driver Installation Commands:"
        output "----------------------------"

        # Detect OS for appropriate commands
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case "$ID" in
                ubuntu|debian)
                    output "# For Ubuntu/Debian:"
                    output "sudo ubuntu-drivers list              # List available drivers"
                    output "sudo ubuntu-drivers install           # Auto-install recommended"
                    output "# OR manually:"
                    output "sudo apt-get install nvidia-driver-535 nvidia-utils-535"
                    output "sudo reboot"
                    ;;
                fedora|rhel|centos)
                    output "# For Fedora/RHEL/CentOS:"
                    output "sudo dnf install akmod-nvidia"
                    output "sudo reboot"
                    ;;
                arch)
                    output "# For Arch Linux:"
                    output "sudo pacman -S nvidia nvidia-utils"
                    output "sudo reboot"
                    ;;
                *)
                    output "# Generic installation:"
                    output "# Visit: https://www.nvidia.com/Download/index.aspx"
                    ;;
            esac
        fi
        output ""
    fi
else
    output "NVIDIA GPU: Not detected"
fi
output ""

# AMD GPU Check
if [ "$AMD_DETECTED" = true ]; then
    output "AMD GPU Status:"
    if command -v rocm-smi &> /dev/null; then
        output "✓ rocm-smi: FOUND"
        rocm-smi 2>&1 | tee -a "$OUTPUT_FILE"
        output "✓ AMD ROCm drivers: INSTALLED"
    else
        output "✗ rocm-smi: NOT FOUND"
        output "✗ AMD ROCm drivers: NOT INSTALLED"
        output ""
        output ">>> ACTION REQUIRED: Install AMD ROCm <<<"
        output ""
        output "Driver Installation:"
        output "----------------------------"
        output "# Visit: https://rocmdocs.amd.com/en/latest/Installation_Guide/Installation-Guide.html"
        output "# ROCm installation is more complex - follow official guide"
    fi
else
    output "AMD GPU: Not detected"
fi
output ""

# Intel GPU Check
if [ "$INTEL_DETECTED" = true ]; then
    output "Intel GPU: Detected (typically integrated graphics)"
    output "Note: Intel GPUs have limited hashcat support"
    output "      Recommend adding dedicated NVIDIA/AMD GPU"
fi
output ""

output "=== MEMORY INFORMATION ==="
free -h | tee -a "$OUTPUT_FILE"
output ""
output "Detailed RAM:"
if [ "$EUID" -eq 0 ]; then
    dmidecode -t memory 2>/dev/null | grep -E "Size|Speed|Type:|Manufacturer" | grep -v "No Module Installed" | tee -a "$OUTPUT_FILE"
else
    output "  (Run with sudo for detailed RAM information)"
fi
output ""

TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -ge 16 ]; then
    output "✓ RAM Status: $TOTAL_RAM GB (Excellent for hashcat)"
elif [ "$TOTAL_RAM" -ge 8 ]; then
    output "✓ RAM Status: $TOTAL_RAM GB (Adequate for hashcat)"
else
    output "⚠ RAM Status: $TOTAL_RAM GB (Minimum - consider upgrade)"
fi
output ""

output "=== STORAGE INFORMATION ==="
df -h | grep -E "Filesystem|/$|/home" | tee -a "$OUTPUT_FILE"
output ""
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE 2>&1 | tee -a "$OUTPUT_FILE"
output ""

ROOT_AVAIL=$(df / | awk 'NR==2 {print $4}')
ROOT_AVAIL_GB=$((ROOT_AVAIL / 1024 / 1024))
output "Available space on /: ~${ROOT_AVAIL_GB}GB"
if [ "$ROOT_AVAIL_GB" -ge 100 ]; then
    output "✓ Storage: Sufficient for large wordlists"
else
    output "⚠ Storage: May need more space for large wordlist collections"
fi
output ""

output "=== OPERATING SYSTEM ==="
if [ -f /etc/os-release ]; then
    cat /etc/os-release | grep -E "PRETTY_NAME|VERSION_ID" | tee -a "$OUTPUT_FILE"
fi
output "Kernel: $(uname -r)"
output ""

output "=== NETWORK INFORMATION ==="
ip addr show | grep -E "^[0-9]|inet " | tee -a "$OUTPUT_FILE"
output ""

output "=== POWER SUPPLY ASSESSMENT ==="
if [ -f /sys/class/power_supply/AC/online ]; then
    output "System Type: Laptop"
    output "⚠ GPU upgrade options limited by power and space"
else
    output "System Type: Desktop/Server"
    output "Note: Check PSU wattage label inside case before GPU upgrade"
    output ""
    output "PSU Requirements for Common GPUs:"
    output "  - GTX 1660 / RTX 3060:     550W+"
    output "  - RTX 4060 / 4060 Ti:      550W+"
    output "  - RTX 4070:                650W+"
    output "  - RTX 4080:                750W+"
    output "  - RTX 4090:                850W+"
fi
output ""

output "=== HASHCAT INSTALLATION STATUS ==="
if command -v hashcat &> /dev/null; then
    output "✓ Hashcat: INSTALLED"
    output "Version: $(hashcat --version 2>&1 | head -1)"
    output ""
    output "Available devices:"
    hashcat -I 2>&1 | grep -A 2 "Backend\|Platform\|Device" | tee -a "$OUTPUT_FILE"
    output ""
    output "To benchmark WPA2 cracking speed:"
    output "  hashcat -b -m 22000"
else
    output "✗ Hashcat: NOT INSTALLED"
    output ""
    output ">>> ACTION REQUIRED: Install hashcat <<<"
    output ""
    output "Installation Commands:"
    output "----------------------------"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                output "sudo apt-get update"
                output "sudo apt-get install -y hashcat hcxtools"
                ;;
            fedora|rhel|centos)
                output "sudo dnf install hashcat"
                ;;
            arch)
                output "sudo pacman -S hashcat"
                ;;
        esac
    fi
fi
output ""

# Check for hcxtools
if command -v hcxpcapngtool &> /dev/null; then
    output "✓ hcxtools: INSTALLED"
else
    output "✗ hcxtools: NOT INSTALLED (needed for PCAP processing)"
    output "  Install: sudo apt-get install hcxtools"
fi
output ""

output "=== CUDA TOOLKIT STATUS ==="
if command -v nvcc &> /dev/null; then
    output "✓ CUDA Toolkit: INSTALLED"
    output "Version: $(nvcc --version | grep release)"
else
    output "✗ CUDA Toolkit: NOT INSTALLED"
    if [ "$NVIDIA_DETECTED" = true ]; then
        output "  Install: sudo apt-get install nvidia-cuda-toolkit"
    fi
fi
output ""

output "=== CURRENT UTILIZATION ==="
output "Load average:"
uptime | tee -a "$OUTPUT_FILE"
output ""
output "Top CPU processes:"
ps aux --sort=-%cpu | head -6 | tee -a "$OUTPUT_FILE"
output ""

if command -v nvidia-smi &> /dev/null; then
    output "GPU Utilization:"
    nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu --format=csv | tee -a "$OUTPUT_FILE"
    output ""
fi

output "========================================="
output "SYSTEM READINESS ASSESSMENT"
output "========================================="
output ""

# Calculate readiness score
READY_SCORE=0
MAX_SCORE=5

# Check GPU
if [ "$NVIDIA_DETECTED" = true ] && command -v nvidia-smi &> /dev/null; then
    output "✓ GPU: Ready (NVIDIA with working drivers)"
    ((READY_SCORE++))
elif [ "$AMD_DETECTED" = true ] && command -v rocm-smi &> /dev/null; then
    output "✓ GPU: Ready (AMD with ROCm)"
    ((READY_SCORE++))
else
    output "✗ GPU: Not ready (no GPU or drivers not installed)"
fi

# Check hashcat
if command -v hashcat &> /dev/null; then
    output "✓ Hashcat: Installed"
    ((READY_SCORE++))
else
    output "✗ Hashcat: Not installed"
fi

# Check hcxtools
if command -v hcxpcapngtool &> /dev/null; then
    output "✓ hcxtools: Installed"
    ((READY_SCORE++))
else
    output "✗ hcxtools: Not installed"
fi

# Check RAM
if [ "$TOTAL_RAM" -ge 8 ]; then
    output "✓ RAM: Sufficient (${TOTAL_RAM}GB)"
    ((READY_SCORE++))
else
    output "⚠ RAM: Limited (${TOTAL_RAM}GB)"
fi

# Check storage
if [ "$ROOT_AVAIL_GB" -ge 50 ]; then
    output "✓ Storage: Sufficient (${ROOT_AVAIL_GB}GB free)"
    ((READY_SCORE++))
else
    output "⚠ Storage: Limited (${ROOT_AVAIL_GB}GB free)"
fi

output ""
output "Readiness Score: $READY_SCORE/$MAX_SCORE"
output ""

if [ "$READY_SCORE" -eq "$MAX_SCORE" ]; then
    output "✓ System is READY for hashcat cracking!"
    output ""
    output "Next steps:"
    output "1. Benchmark performance: hashcat -b -m 22000"
    output "2. Set up cracking infrastructure (see SETUP_GUIDE.md)"
    output "3. Download wordlists to start cracking"
elif [ "$READY_SCORE" -ge 3 ]; then
    output "⚠ System is PARTIALLY READY - minor setup needed"
    output ""
    output "Required actions listed above in respective sections"
else
    output "✗ System is NOT READY - significant setup required"
    output ""
    output "Priority actions:"
    output "1. Install GPU drivers (see GPU section above)"
    output "2. Install hashcat and hcxtools"
    output "3. Reboot system"
    output "4. Re-run this script to verify"
fi

output ""
output "========================================="
output "QUICK SETUP COMMANDS"
output "========================================="
output ""

if [ "$NVIDIA_DETECTED" = true ] && ! command -v nvidia-smi &> /dev/null; then
    output "# Step 1: Install NVIDIA drivers"
    output "sudo ubuntu-drivers install"
    output "sudo reboot"
    output ""
fi

if ! command -v hashcat &> /dev/null; then
    output "# Step 2: Install hashcat and tools"
    output "sudo apt-get update"
    output "sudo apt-get install -y hashcat hcxtools aircrack-ng"
    output ""
fi

if ! command -v nvcc &> /dev/null && [ "$NVIDIA_DETECTED" = true ]; then
    output "# Step 3: Install CUDA toolkit (optional but recommended)"
    output "sudo apt-get install -y nvidia-cuda-toolkit"
    output ""
fi

output "# Step 4: Verify installation"
output "hashcat --version"
output "hashcat -I"
output ""
output "# Step 5: Benchmark WPA2 cracking"
output "hashcat -b -m 22000"
output ""

output "========================================="
output "REPORT SAVED TO: $OUTPUT_FILE"
output "========================================="
output ""
output "You can now:"
output "1. Review this file: cat $OUTPUT_FILE"
output "2. Share for hardware recommendations"
output "3. Compare with other systems"
output "4. Track changes over time"
output ""
