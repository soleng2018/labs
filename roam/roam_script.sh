#!/bin/bash

# WiFi Auto Roaming Script (SSID-based)
# Usage: ./roam_script.sh [SSID] [min_time_minutes] [max_time_minutes] [min_signal_dbm] [interface]

set -euo pipefail

# Default Configuration Values
DEFAULT_SSID="Alonso-ENT"
DEFAULT_MIN_TIME=10
DEFAULT_MAX_TIME=20
DEFAULT_MIN_SIGNAL=-75

# Configuration
INTERFACE=""  # Will be auto-detected or set by user
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

# Global variables for discovered BSSIDs
declare -a AVAILABLE_BSSIDS=()
declare -a BSSID_SIGNALS=()

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

# Function to automatically detect wireless interface
auto_detect_interface() {
    local detected_interface=""

    # Method 1: Look for interfaces with wireless extensions
    local wireless_interfaces
    wireless_interfaces=$(iwconfig 2>/dev/null | grep -E "^[a-zA-Z0-9]+" | awk '{print $1}' | grep -v "lo" || true)

    if [ -n "$wireless_interfaces" ]; then
        # Filter for interfaces that are UP and have wireless capabilities
        local active_wireless=""
        while read -r iface; do
            if [ -n "$iface" ] && ip link show "$iface" up >/dev/null 2>&1; then
                # Check if it's a wireless interface by looking for wireless info
                if iw dev "$iface" info >/dev/null 2>&1; then
                    detected_interface="$iface"
                    break
                fi
            fi
        done <<< "$wireless_interfaces"

        if [ -n "$detected_interface" ]; then
            printf "%s" "$detected_interface"
            return 0
        fi
    fi

    # Method 2: Use iw to list all wireless interfaces
    local iw_interfaces
    iw_interfaces=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' || true)

    if [ -n "$iw_interfaces" ]; then
        # Pick the first UP interface
        while read -r iface; do
            if [ -n "$iface" ] && ip link show "$iface" up >/dev/null 2>&1; then
                detected_interface="$iface"
                break
            fi
        done <<< "$iw_interfaces"

        if [ -n "$detected_interface" ]; then
            printf "%s" "$detected_interface"
            return 0
        fi

        # If no UP interface found, pick the first available
        local first_iface
        first_iface=$(echo "$iw_interfaces" | head -n1)
        if [ -n "$first_iface" ]; then
            detected_interface="$first_iface"
            printf "%s" "$detected_interface"
            return 0
        fi
    fi

    # Method 3: Look in /sys/class/net for wireless interfaces
    for iface in /sys/class/net/*/; do
        iface=$(basename "$iface")
        if [ -d "/sys/class/net/$iface/wireless" ] || [ -L "/sys/class/net/$iface/phy80211" ]; then
            detected_interface="$iface"
            printf "%s" "$detected_interface"
            return 0
        fi
    done

    return 1
}

# Function to validate interface
validate_interface() {
    local interface="$1"

    log_info "Validating interface: $interface"

    # Check if interface exists
    if ! ip link show "$interface" >/dev/null 2>&1; then
        log_error "Interface $interface does not exist"
        return 1
    fi

    # Check if it's a wireless interface using multiple methods
    local is_wireless=false

    # Method 1: Check with iw dev
    if iw dev "$interface" info >/dev/null 2>&1; then
        is_wireless=true
    # Method 2: Check with iwconfig
    elif iwconfig "$interface" 2>/dev/null | grep -q "IEEE 802.11"; then
        is_wireless=true
    # Method 3: Check sysfs
    elif [ -d "/sys/class/net/$interface/wireless" ] || [ -L "/sys/class/net/$interface/phy80211" ]; then
        is_wireless=true
    # Method 4: Check if iwconfig shows wireless extensions
    elif iwconfig "$interface" 2>&1 | grep -qv "no wireless extensions"; then
        is_wireless=true
    fi

    if [ "$is_wireless" = false ]; then
        log_error "Interface $interface is not a wireless interface"
        return 1
    fi

    log_success "Confirmed $interface is a wireless interface"

    # Check if interface is up
    if ! ip link show "$interface" up >/dev/null 2>&1; then
        log_warning "Interface $interface is down, attempting to bring it up..."
        if sudo ip link set "$interface" up; then
            log_success "Interface $interface brought up successfully"
            sleep 2  # Give it time to come up
        else
            log_error "Failed to bring interface $interface up"
            return 1
        fi
    fi

    # Test wpa_cli connectivity - make this less strict since the interface is clearly working
    if timeout 5 sudo wpa_cli -i "$interface" ping >/dev/null 2>&1; then
        log_success "wpa_cli responding on interface $interface"
    else
        log_warning "wpa_cli not responding on interface $interface"
        log_warning "This may be normal if using NetworkManager or other wireless managers"
        log_info "Attempting to verify interface can scan for networks..."

        # Try a simple scan to verify the interface works
        if timeout 10 sudo iw dev "$interface" scan >/dev/null 2>&1; then
            log_success "Interface $interface can perform wireless scans"
        elif timeout 10 iwlist "$interface" scan >/dev/null 2>&1; then
            log_success "Interface $interface can perform wireless scans (via iwlist)"
        else
            log_error "Interface $interface cannot perform wireless operations"
            return 1
        fi
    fi

    log_success "Interface $interface validated successfully"
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

# Function to discover BSSIDs for a given SSID
discover_bssids_for_ssid() {
    local target_ssid="$1"
    local min_signal="$2"
    local attempt=1

    log_info "Discovering BSSIDs for SSID: '$target_ssid'"
    log_info "Minimum signal strength required: ${min_signal} dBm"

    # Clear previous results
    AVAILABLE_BSSIDS=()
    BSSID_SIGNALS=()

    while [ $attempt -le $MAX_SCAN_ATTEMPTS ]; do
        log_info "Discovery scan attempt $attempt/$MAX_SCAN_ATTEMPTS"

        # Perform comprehensive scan
        if perform_comprehensive_scan "full"; then
            # Parse scan results for the target SSID
            local scan_results
            if scan_results=$(timeout $STATUS_TIMEOUT sudo wpa_cli -i "$INTERFACE" scan_results 2>/dev/null); then

                # Process each line looking for our SSID
                local found_any=false
                while IFS=$'\t' read -r bssid frequency signal flags ssid_from_scan; do
                    # Skip header line and empty lines
                    [[ "$bssid" =~ ^bssid ]] && continue
                    [[ -z "$bssid" ]] && continue

                    # Check if this entry matches our target SSID
                    if [ "$ssid_from_scan" = "$target_ssid" ]; then
                        found_any=true

                        # Parse signal strength (remove leading/trailing spaces)
                        signal=$(echo "$signal" | tr -d '[:space:]')

                        # Check if signal is strong enough
                        if [ "$signal" -ge "$min_signal" ]; then
                            log_success "Found suitable BSSID: $bssid (Signal: ${signal} dBm, Freq: ${frequency} MHz)"
                            AVAILABLE_BSSIDS+=("$bssid")
                            BSSID_SIGNALS+=("$signal")
                        else
                            log_warning "Found BSSID with weak signal: $bssid (Signal: ${signal} dBm, below threshold of ${min_signal} dBm)"
                        fi
                    fi
                done <<< "$scan_results"

                if [ "$found_any" = true ]; then
                    # Check if we found enough suitable BSSIDs
                    if [ ${#AVAILABLE_BSSIDS[@]} -ge 2 ]; then
                        log_success "Found ${#AVAILABLE_BSSIDS[@]} suitable BSSIDs for SSID '$target_ssid'"
                        return 0
                    elif [ ${#AVAILABLE_BSSIDS[@]} -eq 1 ]; then
                        log_warning "Found only 1 suitable BSSID for SSID '$target_ssid'. Need at least 2 for roaming."
                    fi
                else
                    log_warning "SSID '$target_ssid' not found in scan results (attempt $attempt)"
                fi
            else
                log_error "Failed to get scan results"
            fi
        fi

        ((attempt++))
        if [ $attempt -le $MAX_SCAN_ATTEMPTS ]; then
            log_info "Waiting 5 seconds before next discovery attempt..."
            sleep 5
        fi
    done

    # Final check and error reporting
    if [ ${#AVAILABLE_BSSIDS[@]} -eq 0 ]; then
        log_error "No suitable BSSIDs found for SSID '$target_ssid' after $MAX_SCAN_ATTEMPTS attempts"
        log_error "Possible reasons:"
        log_error "  - SSID '$target_ssid' doesn't exist or is not broadcasting"
        log_error "  - All available BSSIDs have signal strength below ${min_signal} dBm"
        log_error "  - Network is temporarily unavailable"
        return 1
    elif [ ${#AVAILABLE_BSSIDS[@]} -eq 1 ]; then
        log_error "Found only 1 suitable BSSID for SSID '$target_ssid'"
        log_error "Need at least 2 BSSIDs for roaming functionality"
        log_error "Available BSSID: ${AVAILABLE_BSSIDS[0]} (${BSSID_SIGNALS[0]} dBm)"
        return 1
    fi

    return 1
}

# Function to display discovered BSSIDs
display_discovered_bssids() {
    log_info "=== Discovered BSSIDs ==="
    for i in "${!AVAILABLE_BSSIDS[@]}"; do
        log_info "BSSID $((i+1)): ${AVAILABLE_BSSIDS[$i]} (Signal: ${BSSID_SIGNALS[$i]} dBm)"
    done
    log_info "========================="
}

# Function to check if a specific BSSID is still available with good signal
check_bssid_still_available() {
    local target_bssid="$1"
    local min_signal="$2"

    log_info "Verifying BSSID $target_bssid is still available..."

    # Perform a quick scan
    if perform_comprehensive_scan "quick"; then
        # Check scan results for target BSSID
        local scan_results
        if scan_results=$(timeout $STATUS_TIMEOUT sudo wpa_cli -i "$INTERFACE" scan_results 2>/dev/null); then
            while IFS=$'\t' read -r bssid frequency signal flags ssid; do
                if [ "$bssid" = "$target_bssid" ]; then
                    signal=$(echo "$signal" | tr -d '[:space:]')
                    if [ "$signal" -ge "$min_signal" ]; then
                        log_success "BSSID $target_bssid verified available with signal ${signal} dBm"
                        return 0
                    else
                        log_warning "BSSID $target_bssid found but signal too weak: ${signal} dBm (min: ${min_signal} dBm)"
                        return 1
                    fi
                fi
            done <<< "$scan_results"
        fi
    fi

    log_warning "BSSID $target_bssid not found or signal too weak"
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

# Function to select next BSSID for roaming (round-robin)
get_next_bssid() {
    local current_bssid="$1"
    local current_index=-1

    # Find current BSSID index
    for i in "${!AVAILABLE_BSSIDS[@]}"; do
        if [ "${AVAILABLE_BSSIDS[$i]}" = "$current_bssid" ]; then
            current_index=$i
            break
        fi
    done

    # Select next BSSID (round-robin)
    local next_index
    if [ $current_index -eq -1 ]; then
        # Current BSSID not in our list, start with first one
        next_index=0
    else
        # Move to next BSSID, wrap around if necessary
        next_index=$(((current_index + 1) % ${#AVAILABLE_BSSIDS[@]}))
    fi

    echo "${AVAILABLE_BSSIDS[$next_index]}"
}

# Function to refresh BSSID list periodically
refresh_bssid_list() {
    local target_ssid="$1"
    local min_signal="$2"

    log_info "Refreshing BSSID list for SSID '$target_ssid'..."

    local old_count=${#AVAILABLE_BSSIDS[@]}

    if discover_bssids_for_ssid "$target_ssid" "$min_signal"; then
        local new_count=${#AVAILABLE_BSSIDS[@]}
        log_success "BSSID list refreshed: $old_count -> $new_count available BSSIDs"
        display_discovered_bssids
        return 0
    else
        log_error "Failed to refresh BSSID list"
        return 1
    fi
}

# Function to display usage information
show_usage() {
    echo "WiFi Auto Roaming Script (SSID-based)"
    echo ""
    echo "Usage: $0 [SSID] [min_time_minutes] [max_time_minutes] [min_signal_dbm] [interface]"
    echo ""
    echo "Default values (used if no parameters specified):"
    echo "  SSID                - $DEFAULT_SSID"
    echo "  min_time_minutes    - $DEFAULT_MIN_TIME"
    echo "  max_time_minutes    - $DEFAULT_MAX_TIME"
    echo "  min_signal_dbm      - $DEFAULT_MIN_SIGNAL"
    echo "  interface           - Auto-detected"
    echo ""
    echo "Examples:"
    echo "  $0                                           # Use all defaults"
    echo "  $0 \"MyWiFiNetwork\"                          # Use custom SSID, other defaults"
    echo "  $0 \"MyWiFiNetwork\" 20 30                     # Custom SSID and timing"
    echo "  $0 \"MyWiFiNetwork\" 20 30 -70                 # Custom SSID, timing, and signal"
    echo "  $0 \"MyWiFiNetwork\" 20 30 -70 wlan0           # All custom parameters"
    echo ""
    echo "Parameters:"
    echo "  SSID                - The WiFi network name to roam within"
    echo "  min_time_minutes    - Minimum wait time between roams"
    echo "  max_time_minutes    - Maximum wait time between roams"
    echo "  min_signal_dbm      - Minimum signal strength required"
    echo "  interface           - WiFi interface name (auto-detected if not specified)"
    echo ""
    echo "Available network interfaces:"
    ip link show | grep -E "^[0-9]+" | awk '{print "  " $2}' | sed 's/:$//' || true
}

# Main function
main() {
    # Handle help requests
    if [ $# -eq 1 ] && [[ "$1" =~ ^(-h|--help|help)$ ]]; then
        show_usage
        exit 0
    fi

    # Parse arguments with defaults
    local target_ssid="${1:-$DEFAULT_SSID}"
    local min_time="${2:-$DEFAULT_MIN_TIME}"
    local max_time="${3:-$DEFAULT_MAX_TIME}"
    local min_signal="${4:-$DEFAULT_MIN_SIGNAL}"
    local user_interface="${5:-}"

    # Validate we don't have too many arguments
    if [ $# -gt 5 ]; then
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
            log_error "Please specify interface manually as 5th parameter"
            exit 1
        fi
    fi

    # Validate the interface
    if ! validate_interface "$INTERFACE"; then
        log_error "Interface validation failed"
        exit 1
    fi

    # Validate inputs
    if ! [[ "$min_time" =~ ^[0-9]+$ ]] || ! [[ "$max_time" =~ ^[0-9]+$ ]]; then
        log_error "Time values must be positive integers"
        exit 1
    fi

    if ! [[ "$min_signal" =~ ^-?[0-9]+$ ]]; then
        log_error "Minimum signal value must be an integer (typically negative, e.g., -70)"
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

    if [ -z "$target_ssid" ]; then
        log_error "SSID cannot be empty"
        exit 1
    fi

    log_info "Starting WiFi SSID-based roaming script"
    log_info "Target SSID: '$target_ssid'"
    log_info "Time range: $min_time - $max_time minutes"
    log_info "Minimum signal: $min_signal dBm"
    log_info "Using interface: $INTERFACE"

    # Show which values are defaults vs user-provided
    echo ""
    log_info "=== Configuration Summary ==="
    if [ $# -ge 1 ]; then
        log_info "SSID: '$target_ssid' (user-provided)"
    else
        log_info "SSID: '$target_ssid' (default)"
    fi

    if [ $# -ge 2 ]; then
        log_info "Min Time: $min_time minutes (user-provided)"
    else
        log_info "Min Time: $min_time minutes (default)"
    fi

    if [ $# -ge 3 ]; then
        log_info "Max Time: $max_time minutes (user-provided)"
    else
        log_info "Max Time: $max_time minutes (default)"
    fi

    if [ $# -ge 4 ]; then
        log_info "Signal Threshold: $min_signal dBm (user-provided)"
    else
        log_info "Signal Threshold: $min_signal dBm (default)"
    fi

    if [ $# -ge 5 ]; then
        log_info "Interface: $INTERFACE (user-provided)"
    else
        log_info "Interface: $INTERFACE (auto-detected)"
    fi
    log_info "============================="
    echo ""

    # Display interface information
    log_info "=== Interface Information ==="
    if iw_info=$(iw dev "$INTERFACE" info 2>/dev/null); then
        local ifindex wiphy mac type
        ifindex=$(echo "$iw_info" | grep "ifindex" | awk '{print $2}')
        wiphy=$(echo "$iw_info" | grep "wiphy" | awk '{print $2}')
        mac=$(echo "$iw_info" | grep "addr" | awk '{print $2}')
        type=$(echo "$iw_info" | grep "type" | awk '{print $2}')

        [ -n "$ifindex" ] && log_info "Interface Index: $ifindex"
        [ -n "$wiphy" ] && log_info "Wiphy: $wiphy"
        [ -n "$mac" ] && log_info "MAC Address: $mac"
        [ -n "$type" ] && log_info "Type: $type"
    fi
    log_info "============================="

    # Check if interface exists
    if ! ip link show "$INTERFACE" > /dev/null 2>&1; then
        log_error "Interface $INTERFACE not found"
        exit 1
    fi

    # Discover BSSIDs for the target SSID
    log_info "Discovering available BSSIDs for SSID '$target_ssid'..."
    if ! discover_bssids_for_ssid "$target_ssid" "$min_signal"; then
        exit 1
    fi

    # Display discovered BSSIDs
    display_discovered_bssids

    # Show initial connection status
    show_connection_status

    # Main roaming loop
    local iteration=1
    local refresh_counter=0
    local refresh_interval=10  # Refresh BSSID list every 10 iterations

    while true; do
        log_info "=== Roaming Iteration $iteration ==="

        # Periodically refresh BSSID list
        if [ $((iteration % refresh_interval)) -eq 1 ] && [ $iteration -gt 1 ]; then
            refresh_bssid_list "$target_ssid" "$min_signal"
        fi

        # Check interface health before proceeding
        if ! check_interface_health "$INTERFACE"; then
            log_error "Interface health check failed. Waiting 30 seconds before retry..."
            sleep 30
            continue
        fi

        # Get current BSSID
        local current_bssid
        current_bssid=$(get_current_bssid)
        log_info "Currently connected to: ${current_bssid}"

        # Select next BSSID for roaming
        local target_bssid
        target_bssid=$(get_next_bssid "$current_bssid")
        log_info "Next target BSSID: $target_bssid"

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

        log_info "Wait time completed. Preparing to roam to: $target_bssid"

        # Check if target BSSID is still available with good signal
        if check_bssid_still_available "$target_bssid" "$min_signal"; then
            if perform_roam "$target_bssid"; then
                # Show post-roam connection status
                show_connection_status
                log_success "Roaming cycle $iteration completed successfully"
            else
                log_error "Roaming failed in iteration $iteration, will retry in next cycle"
            fi
        else
            log_error "Target BSSID not available or signal too weak in iteration $iteration"
            log_info "Will refresh BSSID list and try again in next cycle"
        fi

        ((iteration++))
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