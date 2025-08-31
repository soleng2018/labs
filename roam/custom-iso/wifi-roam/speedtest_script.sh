#!/bin/bash

# WiFi Speedtest Script
# This script runs speedtest-cli periodically with random timing intervals

set -euo pipefail

# Default Configuration Values
DEFAULT_MIN_TIME=30
DEFAULT_MAX_TIME=120

# Configuration
INTERFACE=""  # Will be auto-detected or set by user

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if speedtest-cli is installed
check_speedtest_installed() {
    if command -v speedtest-cli >/dev/null 2>&1; then
        log_success "speedtest-cli is already installed"
        return 0
    fi
    
    log_warning "speedtest-cli is not installed"
    log_info "Attempting to install speedtest-cli..."
    
    # Try to install speedtest-cli
    if apt-get update 2>/dev/null && apt-get install -y speedtest-cli 2>/dev/null; then
        log_success "speedtest-cli installed successfully"
        return 0
    else
        log_error "Failed to install speedtest-cli"
        log_warning "Speedtest functionality will be disabled"
        log_warning "This may be due to offline installation or missing package repositories"
        
        # Check if we can create a dummy speedtest command
        if [ ! -f "/usr/local/bin/speedtest-cli" ]; then
            log_info "Creating dummy speedtest-cli for offline use"
            cat > /usr/local/bin/speedtest-cli << 'EOF'
#!/bin/bash
echo "speedtest-cli not available (offline installation)"
echo "Ping: N/A ms"
echo "Download: N/A Mbit/s" 
echo "Upload: N/A Mbit/s"
exit 0
EOF
            chmod +x /usr/local/bin/speedtest-cli
            log_warning "Created dummy speedtest-cli that returns placeholder values"
        fi
        return 0  # Don't fail the entire script
    fi
}

# Function to check network connectivity
check_network_connectivity() {
    local interface="$1"
    
    # Check if interface has IP address
    if ! ip addr show "$interface" | grep -q "inet "; then
        log_warning "Interface $interface has no IP address"
        return 1
    fi
    
    # Check if we can reach the internet
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_warning "No internet connectivity detected"
        return 1
    fi
    
    return 0
}

# Function to run speedtest
run_speedtest() {
    local interface="$1"
    
    log_info "Running speedtest on interface $interface..."
    
    # Check network connectivity first
    if ! check_network_connectivity "$interface"; then
        log_warning "Skipping speedtest due to network issues"
        return 1
    fi
    
    # Run speedtest with timeout
    local output
    if output=$(timeout 300 speedtest-cli --simple 2>&1); then
        log_success "Speedtest completed successfully"
        echo "$output" | while IFS= read -r line; do
            if [[ "$line" =~ ^(Download|Upload|Ping): ]]; then
                log_info "  $line"
            fi
        done
        return 0
    else
        log_error "Speedtest failed or timed out"
        return 1
    fi
}

# Function to generate random time in minutes
generate_random_time() {
    local min_time="$1"
    local max_time="$2"

    # Generate random number between min and max (inclusive)
    echo $((RANDOM % (max_time - min_time + 1) + min_time))
}

# Function to display usage information
show_usage() {
    echo "WiFi Speedtest Script"
    echo ""
    echo "Usage: $0 [min_time_minutes] [max_time_minutes] [interface]"
    echo ""
    echo "Default values (used if no parameters specified):"
    echo "  min_time_minutes    - $DEFAULT_MIN_TIME"
    echo "  max_time_minutes    - $DEFAULT_MAX_TIME"
    echo "  interface           - Auto-detected"
    echo ""
    echo "Examples:"
    echo "  $0                                           # Use all defaults"
    echo "  $0 60 180                                    # Custom timing (1-3 hours)"
    echo "  $0 60 180 wlan0                              # Custom timing and interface"
    echo ""
    echo "Parameters:"
    echo "  min_time_minutes    - Minimum wait time between speedtests"
    echo "  max_time_minutes    - Maximum wait time between speedtests"
    echo "  interface           - WiFi interface name (auto-detected if not specified)"
}

# Function to auto-detect wireless interface
auto_detect_interface() {
    local detected_interface=""

    # Method 1: Use iw to list all wireless interfaces
    local iw_interfaces
    iw_interfaces=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' || true)

    if [ -n "$iw_interfaces" ]; then
        # Pick the first available interface
        local first_iface
        first_iface=$(echo "$iw_interfaces" | head -n1)
        if [ -n "$first_iface" ]; then
            detected_interface="$first_iface"
            printf "%s" "$detected_interface"
            return 0
        fi
    fi

    # Method 2: Look in /sys/class/net for wireless interfaces
    for iface in /sys/class/net/*/; do
        iface=$(basename "$iface")
        if [ -d "/sys/class/net/$iface/wireless" ] || [ -L "/sys/class/net/$iface/phy80211" ]; then
            detected_interface="$iface"
            printf "%s" "$detected_interface"
            return 0
        fi
    done

    # Method 3: Check common wireless interface names
    for iface in wlan0 wlan1 wlx* wl*; do
        if ip link show "$iface" >/dev/null 2>&1; then
            detected_interface="$iface"
            printf "%s" "$detected_interface"
            return 0
        fi
    done

    return 1
}

# Main function
main() {
    # Handle help requests
    if [ $# -eq 1 ] && [[ "$1" =~ ^(-h|--help|help)$ ]]; then
        show_usage
        exit 0
    fi

    # Parse arguments with defaults
    local min_time="${1:-$DEFAULT_MIN_TIME}"
    local max_time="${2:-$DEFAULT_MAX_TIME}"
    local user_interface="${3:-}"

    # Validate we don't have too many arguments
    if [ $# -gt 3 ]; then
        log_error "Too many arguments provided"
        show_usage
        exit 1
    fi

    # Set up interface - either user-specified or auto-detected
    if [ -n "$user_interface" ]; then
        log_info "Using user-specified interface: $user_interface"
        INTERFACE="$user_interface"
    else
        log_info "No interface specified, attempting auto-detection..."
        if INTERFACE=$(auto_detect_interface); then
            log_success "Auto-detected wireless interface: $INTERFACE"
        else
            log_error "Could not auto-detect wireless interface"
            log_error "Available network interfaces:"
            ip link show | grep -E "^[0-9]+" | awk '{print "  " $2}' | sed 's/:$//' || true
            log_error "Please specify interface manually as 3rd parameter"
            exit 1
        fi
    fi

    # Validate the interface
    if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
        log_error "Interface $INTERFACE does not exist"
        exit 1
    fi

    # Validate inputs
    if ! [[ "$min_time" =~ ^[0-9]+$ ]] || ! [[ "$max_time" =~ ^[0-9]+$ ]]; then
        log_error "Time values must be positive integers"
        exit 1
    fi

    if [ "$min_time" -gt "$max_time" ]; then
        log_error "Minimum time cannot be greater than maximum time"
        exit 1
    fi

    if [ "$min_time" -eq 0 ]; then
        log_error "Minimum time must be greater than 0"
        exit 1
    fi

    log_info "Starting WiFi Speedtest Script"
    log_info "Time range: $min_time - $max_time minutes"
    log_info "Using interface: $INTERFACE"

    # Check if speedtest-cli is installed
    check_speedtest_installed

    # Main speedtest loop
    local iteration=1
    
    while true; do
        log_info "=== Speedtest Iteration $iteration ==="
        
        # Run speedtest
        if run_speedtest "$INTERFACE"; then
            log_success "Speedtest iteration $iteration completed successfully"
        else
            log_warning "Speedtest iteration $iteration had issues"
        fi
        
        # Generate random wait time for next speedtest
        local wait_time
        wait_time=$(generate_random_time "$min_time" "$max_time")
        log_info "Randomly selected wait time: $wait_time minutes"
        
        # Convert to seconds and wait
        local wait_seconds=$((wait_time * 60))
        log_info "Waiting $wait_seconds seconds before next speedtest..."
        
        # Wait with periodic status updates
        local elapsed=0
        local update_interval=300  # Update every 5 minutes
        
        while [ $elapsed -lt $wait_seconds ]; do
            local remaining=$((wait_seconds - elapsed))
            if [ $((elapsed % update_interval)) -eq 0 ] && [ $elapsed -gt 0 ]; then
                log_info "Still waiting... $(((remaining + 59) / 60)) minutes remaining"
            fi
            sleep 60
            elapsed=$((elapsed + 60))
        done
        
        ((iteration++))
        echo ""
        
        # Add a small delay between iterations
        log_info "Pausing 10 seconds before next iteration..."
        sleep 10
    done
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}[INFO]${NC} Script interrupted by user. Exiting..."; exit 0' INT TERM

# Run main function with all arguments
main "$@"

