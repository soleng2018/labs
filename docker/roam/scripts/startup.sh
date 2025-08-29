#!/bin/bash

# WiFi Roaming Container Startup Script
# This script configures the WiFi interface and wpa_supplicant

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[STARTUP-INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[STARTUP-SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[STARTUP-WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[STARTUP-ERROR]${NC} $1"
}

# Function to validate required environment variables
validate_environment() {
    local missing_vars=()
    
    # Check required variables
    [ -z "${SSID_NAME:-}" ] && missing_vars+=("SSID_NAME")
    [ -z "${EAP_USERNAME:-}" ] && missing_vars+=("EAP_USERNAME")
    [ -z "${EAP_PASSWORD:-}" ] && missing_vars+=("EAP_PASSWORD")
    [ -z "${MIN_TIME:-}" ] && missing_vars+=("MIN_TIME")
    [ -z "${MAX_TIME:-}" ] && missing_vars+=("MAX_TIME")
    [ -z "${USB_HOSTBUS:-}" ] && missing_vars+=("USB_HOSTBUS")
    [ -z "${USB_HOSTADDR:-}" ] && missing_vars+=("USB_HOSTADDR")
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Please check your .env file and ensure all required variables are set"
        return 1
    fi
    
    log_success "All required environment variables are set"
    return 0
}

# Function to wait for USB device
wait_for_usb_device() {
    local bus="$1"
    local addr="$2"
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for USB device at Bus ${bus} Device ${addr}..."
    
    while [ $attempt -le $max_attempts ]; do
        if lsusb -s "${bus}:${addr}" >/dev/null 2>&1; then
            log_success "USB device found at Bus ${bus} Device ${addr}"
            lsusb -s "${bus}:${addr}"
            return 0
        fi
        
        log_warning "USB device not found (attempt ${attempt}/${max_attempts}), waiting 2 seconds..."
        sleep 2
        ((attempt++))
    done
    
    log_error "USB WiFi device not found after ${max_attempts} attempts"
    log_error "Please verify USB_HOSTBUS and USB_HOSTADDR in your .env file"
    log_info "Available USB devices:"
    lsusb
    return 1
}

# Function to detect WiFi interface
detect_wifi_interface() {
    local max_attempts=30
    local attempt=1
    
    log_info "Detecting WiFi interface..."
    
    while [ $attempt -le $max_attempts ]; do
        # Method 1: Use iw to list wireless interfaces
        local wireless_interfaces
        if wireless_interfaces=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}'); then
            if [ -n "$wireless_interfaces" ]; then
                local interface
                interface=$(echo "$wireless_interfaces" | head -n1)
                if [ -n "$interface" ]; then
                    log_success "Detected WiFi interface: $interface"
                    echo "$interface"
                    return 0
                fi
            fi
        fi
        
        # Method 2: Check /sys/class/net for wireless interfaces
        for iface in /sys/class/net/*/; do
            iface=$(basename "$iface")
            if [ -d "/sys/class/net/$iface/wireless" ] || [ -L "/sys/class/net/$iface/phy80211" ]; then
                log_success "Detected WiFi interface: $iface"
                echo "$iface"
                return 0
            fi
        done
        
        log_warning "WiFi interface not detected (attempt ${attempt}/${max_attempts}), waiting 2 seconds..."
        sleep 2
        ((attempt++))
    done
    
    log_error "Failed to detect WiFi interface after ${max_attempts} attempts"
    log_info "Available network interfaces:"
    ip link show
    return 1
}

# Function to bring up WiFi interface
setup_wifi_interface() {
    local interface="$1"
    
    log_info "Setting up WiFi interface: $interface"
    
    # Bring interface up
    if ! ip link show "$interface" up >/dev/null 2>&1; then
        log_info "Bringing up interface $interface..."
        if sudo ip link set "$interface" up; then
            log_success "Interface $interface brought up successfully"
            sleep 3  # Give it time to initialize
        else
            log_error "Failed to bring up interface $interface"
            return 1
        fi
    else
        log_info "Interface $interface is already up"
    fi
    
    # Verify interface is operational
    if iw dev "$interface" info >/dev/null 2>&1; then
        log_success "Interface $interface is operational"
        
        # Display interface information
        log_info "Interface $interface details:"
        iw dev "$interface" info | while read -r line; do
            log_info "  $line"
        done
        
        return 0
    else
        log_error "Interface $interface is not operational"
        return 1
    fi
}

# Function to create wpa_supplicant configuration
create_wpa_config() {
    local config_file="/etc/wpa_supplicant/wpa_supplicant.conf"
    local template_file="/app/config/wpa_supplicant.conf.template"
    
    log_info "Creating wpa_supplicant configuration..."
    
    if [ ! -f "$template_file" ]; then
        log_error "Template file not found: $template_file"
        return 1
    fi
    
    # Create configuration directory
    sudo mkdir -p "$(dirname "$config_file")"
    
    # Replace template variables with actual values
    sudo cp "$template_file" "$config_file"
    
    # Remove quotes from SSID_NAME for processing, but preserve spaces
    local clean_ssid_name
    clean_ssid_name=$(echo "$SSID_NAME" | sed 's/^"//;s/"$//')
    
    sudo sed -i "s/{{SSID_NAME}}/$clean_ssid_name/g" "$config_file"
    sudo sed -i "s/{{EAP_USERNAME}}/$EAP_USERNAME/g" "$config_file"
    sudo sed -i "s/{{EAP_PASSWORD}}/$EAP_PASSWORD/g" "$config_file"
    
    log_success "wpa_supplicant configuration created at $config_file"
    
    # Show configuration (without password)
    log_info "Configuration preview:"
    sudo cat "$config_file" | grep -v "password=" | while read -r line; do
        log_info "  $line"
    done
    
    return 0
}

# Function to start wpa_supplicant
start_wpa_supplicant() {
    local interface="$1"
    local config_file="/etc/wpa_supplicant/wpa_supplicant.conf"
    
    log_info "Starting wpa_supplicant for interface $interface..."
    
    # Kill any existing wpa_supplicant processes
    if sudo pkill -f "wpa_supplicant.*$interface" 2>/dev/null; then
        log_info "Stopped existing wpa_supplicant processes"
        sleep 2
    fi
    
    # Start wpa_supplicant in the background
    local wpa_cmd="wpa_supplicant -B -i $interface -c $config_file -D nl80211,wext"
    
    if sudo $wpa_cmd; then
        log_success "wpa_supplicant started successfully"
        sleep 5  # Give it time to initialize
        
        # Verify wpa_supplicant is running and responding
        if timeout 10 sudo wpa_cli -i "$interface" ping >/dev/null 2>&1; then
            log_success "wpa_supplicant is responding on interface $interface"
            
            # Show connection status
            log_info "Initial connection status:"
            sudo wpa_cli -i "$interface" status | while read -r line; do
                log_info "  $line"
            done
            
            return 0
        else
            log_error "wpa_supplicant not responding properly"
            return 1
        fi
    else
        log_error "Failed to start wpa_supplicant"
        return 1
    fi
}

# Function to wait for network connection
wait_for_connection() {
    local interface="$1"
    local max_attempts=60  # Wait up to 60 attempts (2 minutes)
    local attempt=1
    
    log_info "Waiting for network connection on $interface..."
    
    while [ $attempt -le $max_attempts ]; do
        local wpa_state
        if wpa_state=$(timeout 5 sudo wpa_cli -i "$interface" status 2>/dev/null | grep "^wpa_state=" | cut -d'=' -f2); then
            if [ "$wpa_state" = "COMPLETED" ]; then
                log_success "WiFi connection established!"
                
                # Show detailed connection info
                log_info "Connection details:"
                sudo wpa_cli -i "$interface" status | grep -E "(ssid|bssid|freq|key_mgmt)" | while read -r line; do
                    log_success "  $line"
                done
                
                return 0
            else
                log_info "Connection state: $wpa_state (attempt ${attempt}/${max_attempts})"
            fi
        else
            log_warning "Could not get connection status (attempt ${attempt}/${max_attempts})"
        fi
        
        sleep 2
        ((attempt++))
    done
    
    log_warning "Network connection not established within expected time"
    log_warning "This may be normal - continuing with roaming script"
    return 0  # Don't fail here, let roaming script handle connection issues
}

# Main startup function
main() {
    log_info "Starting WiFi Roaming Container..."
    log_info "Container: ${CONTAINER_NAME:-wifi-roam}"
    
    # Validate environment
    if ! validate_environment; then
        exit 1
    fi
    
    # Wait for USB device
    if ! wait_for_usb_device "$USB_HOSTBUS" "$USB_HOSTADDR"; then
        exit 1
    fi
    
    # Detect WiFi interface
    local wifi_interface
    if ! wifi_interface=$(detect_wifi_interface); then
        exit 1
    fi
    
    # Setup WiFi interface
    if ! setup_wifi_interface "$wifi_interface"; then
        exit 1
    fi
    
    # Create wpa_supplicant configuration
    if ! create_wpa_config; then
        exit 1
    fi
    
    # Start wpa_supplicant
    if ! start_wpa_supplicant "$wifi_interface"; then
        exit 1
    fi
    
    # Wait for initial connection
    wait_for_connection "$wifi_interface"
    
    log_success "WiFi startup completed successfully!"
    log_info "WiFi Interface: $wifi_interface"
    log_info "SSID: $SSID_NAME"
    log_info "Username: $EAP_USERNAME"
    log_info "Roaming interval: ${MIN_TIME}-${MAX_TIME} minutes"
    log_info "Signal threshold: ${SIGNAL_THRESHOLD} dBm"
    
    # Export interface name for roaming script
    echo "$wifi_interface" > /app/config/wifi_interface.txt
    
    log_info "Starting roaming script..."
    return 0
}

# Run main function
main "$@"
