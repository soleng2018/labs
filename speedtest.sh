#!/bin/bash

# WiFi Auto Roaming Script
# Usage: ./roam_script.sh <BSSID1> <BSSID2> <min_time_minutes> <max_time_minutes>

set -euo pipefail

# Configuration
INTERFACE="wlx5c628bed927b"
# Extended frequency list covering all common 2.4GHz and 5GHz channels
SCAN_FREQUENCIES_2G="2412,2417,2422,2427,2432,2437,2442,2447,2452,2457,2462,2467,2472,2484"
SCAN_FREQUENCIES_5G="5180,5200,5220,5240,5260,5280,5300,5320,5500,5520,5540,5560,5580,5600,5620,5640,5660,5680,5700,5720,5745,5765,5785,5805,5825"
SCAN_FREQUENCIES_ALL="${SCAN_FREQUENCIES_2G},${SCAN_FREQUENCIES_5G}"
MAX_SCAN_ATTEMPTS=5
SCAN_WAIT_TIME=3
STATUS_TIMEOUT=10  # Timeout for status commands
COMPREHENSIVE_SCAN_WAIT=5  # Extra wait time for comprehensive scans

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

# Function to validate BSSID format
validate_bssid() {
    local bssid="$1"
    if [[ ! "$bssid" =~ ^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}$ ]]; then
        log_error "Invalid BSSID format: $bssid"
        return 1
    fi
    return 0
}

# Function to perform comprehensive scan across all frequencies
perform_comprehensive_scan() {
    local scan_type="$1"  # "quick" or "full"
    local frequencies

    if [ "$scan_type" = "full" ]; then
        frequencies="$SCAN_FREQUENCIES_ALL"
        log_info "Performing comprehensive scan across all 2.4GHz and 5GHz frequencies"
    else
        frequencies="$SCAN_FREQUENCIES_2G"
        log_info "Performing quick scan on 2.4GHz frequencies"
    fi

    log_info "Scanning frequencies: $frequencies"

    # Trigger scan with specified frequencies
    if timeout $STATUS_TIMEOUT sudo wpa_cli -i "$INTERFACE" scan freq="$frequencies" > /dev/null 2>&1; then
        if [ "$scan_type" = "full" ]; then
            log_info "Comprehensive scan triggered, waiting ${COMPREHENSIVE_SCAN_WAIT}s for results..."
            sleep $COMPREHENSIVE_SCAN_WAIT
        else
            log_info "Quick scan triggered, waiting ${SCAN_WAIT_TIME}s for results..."
            sleep $SCAN_WAIT_TIME
        fi
        return 0
    else
        log_warning "Scan failed or timed out"
        return 1
    fi
}

# Function to check if BSSID is available in scan results
check_bssid_available() {
    local target_bssid="$1"
    local attempt=1

    log_info "Checking if BSSID $target_bssid is available..."

    while [ $attempt -le $MAX_SCAN_ATTEMPTS ]; do
        log_info "Scan attempt $attempt/$MAX_SCAN_ATTEMPTS"

        # First try a quick 2.4GHz scan
        if perform_comprehensive_scan "quick"; then
            # Check scan results for target BSSID with timeout
            if timeout $STATUS_TIMEOUT sudo wpa_cli -i "$INTERFACE" scan_results | grep -qi "$target_bssid"; then
                log_success "BSSID $target_bssid found in quick scan results"
                return 0
            fi
        fi

        # If not found in quick scan and we haven't tried full scan yet, try comprehensive scan
        if [ $attempt -eq 1 ] || [ $attempt -eq $MAX_SCAN_ATTEMPTS ]; then
            log_info "Target not found in quick scan, trying comprehensive scan..."
            if perform_comprehensive_scan "full"; then
                # Check scan results for target BSSID with timeout
                if timeout $STATUS_TIMEOUT sudo wpa_cli -i "$INTERFACE" scan_results | grep -qi "$target_bssid"; then
                    log_success "BSSID $target_bssid found in comprehensive scan results"
                    return 0
                fi
            fi
        fi

        log_warning "BSSID $target_bssid not found in scan results (attempt $attempt)"

        ((attempt++))
        if [ $attempt -le $MAX_SCAN_ATTEMPTS ]; then
            log_info "Waiting 5 seconds before next scan attempt..."
            sleep 5
        fi
    done

    log_error "BSSID $target_bssid not found after $MAX_SCAN_ATTEMPTS attempts"
    return 1
}

# Function to perform roaming with verification
perform_roam() {
    local target_bssid="$1"

    log_info "Attempting to roam to BSSID: $target_bssid"

    # Execute roam command
    if timeout $STATUS_TIMEOUT sudo wpa_cli -i "$INTERFACE" roam "$target_bssid" | grep -q "OK"; then
        log_success "Roam command executed successfully for $target_bssid"

        # Give the connection time to stabilize
        log_info "Waiting 10 seconds for connection to stabilize..."
        sleep 10

        # Verify we actually connected to the target BSSID
        local new_bssid
        new_bssid=$(get_current_bssid)

        if [ "$new_bssid" = "$target_bssid" ]; then
            log_success "Successfully roamed and connected to $target_bssid"
            return 0
        else
            log_warning "Roam command succeeded but connected to $new_bssid instead of $target_bssid"
            # This might still be acceptable if it's the same network
            return 0
        fi
    else
        log_error "Roaming to $target_bssid failed or timed out"
        return 1
    fi
}

# Function to get current BSSID with timeout and error handling
get_current_bssid() {
    local current_bssid
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_info "Getting current BSSID (attempt $attempt/$max_attempts)..."

        # Use timeout to prevent hanging
        if current_bssid=$(timeout $STATUS_TIMEOUT sudo wpa_cli -i "$INTERFACE" status 2>/dev/null | grep "^bssid=" | cut -d'=' -f2); then
            if [ -n "$current_bssid" ]; then
                echo "$current_bssid"
                return 0
            fi
        fi

        log_warning "Failed to get current BSSID (attempt $attempt), retrying..."
        sleep 2
        ((attempt++))
    done

    log_warning "Could not determine current BSSID after $max_attempts attempts"
    echo "unknown"
    return 1
}

# Function to display current connection status
show_connection_status() {
    log_info "=== Current Connection Status ==="

    # Get current BSSID
    local current_bssid
    current_bssid=$(get_current_bssid)
    log_info "Connected BSSID: $current_bssid"

    # Get signal strength and other info
    if timeout $STATUS_TIMEOUT sudo wpa_cli -i "$INTERFACE" status > /dev/null 2>&1; then
        local status_output
        status_output=$(timeout $STATUS_TIMEOUT sudo wpa_cli -i "$INTERFACE" status 2>/dev/null)

        local ssid
        ssid=$(echo "$status_output" | grep "^ssid=" | cut -d'=' -f2)
        [ -n "$ssid" ] && log_info "SSID: $ssid"

        local freq
        freq=$(echo "$status_output" | grep "^freq=" | cut -d'=' -f2)
        [ -n "$freq" ] && log_info "Frequency: $freq MHz"

        local wpa_state
        wpa_state=$(echo "$status_output" | grep "^wpa_state=" | cut -d'=' -f2)
        [ -n "$wpa_state" ] && log_info "WPA State: $wpa_state"
    fi

    # Get signal strength
    if timeout $STATUS_TIMEOUT sudo wpa_cli -i "$INTERFACE" signal_poll > /dev/null 2>&1; then
        local signal_info
        signal_info=$(timeout $STATUS_TIMEOUT sudo wpa_cli -i "$INTERFACE" signal_poll 2>/dev/null)

        local rssi
        rssi=$(echo "$signal_info" | grep "^RSSI=" | cut -d'=' -f2)
        [ -n "$rssi" ] && log_info "Signal Strength: $rssi dBm"
    fi

    log_info "================================="
}

# Function to generate random time in minutes
generate_random_time() {
    local min_time="$1"
    local max_time="$2"

    # Generate random number between min and max (inclusive)
    echo $((RANDOM % (max_time - min_time + 1) + min_time))
}

# Function to check if interface is still working
check_interface_health() {
    local interface="$1"

    # Check if interface exists and is up
    if ! ip link show "$interface" up > /dev/null 2>&1; then
        log_error "Interface $interface is down or doesn't exist"
        return 1
    fi

    # Try a simple wpa_cli command with timeout
    if ! timeout 5 sudo wpa_cli -i "$interface" ping > /dev/null 2>&1; then
        log_warning "wpa_cli not responding properly on interface $interface"
        return 1
    fi

    return 0
}

# Main function
main() {
    # Check arguments
    if [ $# -ne 4 ]; then
        echo "Usage: $0 <BSSID1> <BSSID2> <min_time_minutes> <max_time_minutes>"
        echo "Example: $0 26:72:4a:16:52:d7 26:72:4a:18:39:99 20 30"
        exit 1
    fi

    local bssid1="$1"
    local bssid2="$2"
    local min_time="$3"
    local max_time="$4"

    # Validate inputs
    validate_bssid "$bssid1" || exit 1
    validate_bssid "$bssid2" || exit 1

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

    log_info "Starting WiFi roaming script"
    log_info "BSSID 1: $bssid1"
    log_info "BSSID 2: $bssid2"
    log_info "Time range: $min_time - $max_time minutes"
    log_info "Interface: $INTERFACE"
    log_info "Status timeout: $STATUS_TIMEOUT seconds"
    log_info "2.4GHz frequencies: $SCAN_FREQUENCIES_2G"
    log_info "5GHz frequencies: $SCAN_FREQUENCIES_5G"

    # Check if interface exists
    if ! ip link show "$INTERFACE" > /dev/null 2>&1; then
        log_error "Interface $INTERFACE not found"
        exit 1
    fi

    # Show initial connection status
    show_connection_status

    # Main roaming loop
    local current_target="$bssid1"
    local next_target="$bssid2"
    local iteration=1

    while true; do
        log_info "=== Roaming Iteration $iteration ==="

        # Check interface health before proceeding
        if ! check_interface_health "$INTERFACE"; then
            log_error "Interface health check failed. Waiting 30 seconds before retry..."
            sleep 30
            continue
        fi

        # Get current BSSID with error handling
        local current_bssid
        current_bssid=$(get_current_bssid)
        log_info "Currently connected to: ${current_bssid}"

        # Generate random wait time
        local wait_time
        wait_time=$(generate_random_time "$min_time" "$max_time")
        log_info "Randomly selected wait time: $wait_time minutes"

        # Convert to seconds and wait
        local wait_seconds=$((wait_time * 60))
        log_info "Waiting $wait_seconds seconds before next roam..."

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

        log_info "Wait time completed. Preparing to roam to: $current_target"

        # Perform comprehensive scan before roaming
        log_info "Performing pre-roam comprehensive scan to ensure all APs are detected..."
        perform_comprehensive_scan "full"

        # Check if target BSSID is available and roam
        if check_bssid_available "$current_target"; then
            if perform_roam "$current_target"; then
                # Show post-roam connection status
                show_connection_status

                # Swap targets for next iteration
                local temp="$current_target"
                current_target="$next_target"
                next_target="$temp"

                log_success "Roaming cycle $iteration completed successfully"
            else
                log_error "Roaming failed in iteration $iteration, will retry in next cycle"
            fi
        else
            log_error "Target BSSID not available in iteration $iteration, will retry in next cycle"
        fi

        ((iteration++))
        log_info "Next target will be: $current_target"
        echo ""

        # Add a small delay between iterations to prevent rapid cycling
        log_info "Pausing 10 seconds before next iteration..."
        sleep 10
    done
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}[INFO]${NC} Script interrupted by user. Exiting..."; exit 0' INT TERM

# Run main function with all arguments
main "$@"