#!/bin/bash

# WPA Supplicant Wrapper Script
# This script detects the wireless interface and starts wpa_supplicant

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
WPA_CONF="$SCRIPT_DIR/wpa_supplicant.conf"
LOG_FILE="/var/log/wpa_supplicant.log"

# Function to detect wireless interface
detect_wireless_interface() {
    local interfaces=$(ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print $2}' | grep -v lo)
    
    for iface in $interfaces; do
        # Check if interface is wireless
        if iw dev "$iface" info >/dev/null 2>&1; then
            echo "$iface"
            return 0
        fi
    done
    
    # Fallback: check common wireless interface names
    for iface in wlx* wlan* wlp* wifi*; do
        if ip link show "$iface" >/dev/null 2>&1; then
            echo "$iface"
            return 0
        fi
    done
    
    return 1
}

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Main function
main() {
    log_message "Starting WPA Supplicant wrapper..."
    
    # Detect wireless interface
    log_message "Detecting wireless interface..."
    WIFI_INTERFACE=$(detect_wireless_interface)
    
    if [[ -z "$WIFI_INTERFACE" ]]; then
        log_message "ERROR: No wireless interface found"
        exit 1
    fi
    
    log_message "Using wireless interface: $WIFI_INTERFACE"
    
    # Check if config file exists
    if [[ ! -f "$WPA_CONF" ]]; then
        log_message "ERROR: WPA config file not found: $WPA_CONF"
        exit 1
    fi
    
    # Start wpa_supplicant
    log_message "Starting wpa_supplicant on interface $WIFI_INTERFACE..."
    exec /sbin/wpa_supplicant -u -s -O /run/wpa_supplicant -c "$WPA_CONF" -i "$WIFI_INTERFACE" -f "$LOG_FILE"
}

# Run main function
main "$@"
