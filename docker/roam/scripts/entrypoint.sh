#!/bin/bash

# WiFi Roaming Container Entrypoint Script
# This is the main entry point for the container

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[ENTRYPOINT-INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_success() {
    echo -e "${GREEN}[ENTRYPOINT-SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_warning() {
    echo -e "${YELLOW}[ENTRYPOINT-WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo -e "${RED}[ENTRYPOINT-ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# Function to handle cleanup on exit
cleanup() {
    log_info "Container shutdown initiated..."
    
    # Kill wpa_supplicant processes
    if pgrep wpa_supplicant > /dev/null; then
        log_info "Stopping wpa_supplicant..."
        sudo pkill wpa_supplicant || true
    fi
    
    # Kill roaming script
    if pgrep -f roam.sh > /dev/null; then
        log_info "Stopping roaming script..."
        pkill -f roam.sh || true
    fi
    
    log_info "Cleanup completed"
    exit 0
}

# Set up signal handlers for graceful shutdown
trap cleanup SIGTERM SIGINT

# Function to create log directory
setup_logging() {
    mkdir -p /app/logs
    
    # Create log files
    touch /app/logs/startup.log
    touch /app/logs/roaming.log
    touch /app/logs/wpa_supplicant.log
    
    log_info "Log directory created at /app/logs"
}

# Function to display container information
show_container_info() {
    log_info "=== WiFi Roaming Container Started ==="
    log_info "Container Name: ${CONTAINER_NAME:-wifi-roam}"
    log_info "SSID: ${SSID_NAME:-not-set}"
    log_info "EAP Username: ${EAP_USERNAME:-not-set}"
    log_info "Roaming Interval: ${MIN_TIME:-not-set} - ${MAX_TIME:-not-set} minutes"
    log_info "USB Device: Bus ${USB_HOSTBUS:-not-set} Device ${USB_HOSTADDR:-not-set}"
    log_info "Signal Threshold: ${SIGNAL_THRESHOLD:--75} dBm"
    log_info "Scan Interval: ${SCAN_INTERVAL:-30} seconds"
    log_info "========================================"
}

# Function to start system services
start_system_services() {
    log_info "Starting system services..."
    
    # Start dbus (required for wpa_supplicant)
    if ! pgrep dbus-daemon > /dev/null; then
        log_info "Starting dbus service..."
        sudo service dbus start || {
            log_warning "Failed to start dbus service via service command, trying manual start..."
            sudo dbus-daemon --system --fork || {
                log_error "Failed to start dbus daemon"
                return 1
            }
        }
    else
        log_info "dbus is already running"
    fi
    
    log_success "System services started"
    return 0
}

# Function to run startup script
run_startup() {
    log_info "Running WiFi startup configuration..."
    
    if /app/scripts/startup.sh 2>&1 | tee -a /app/logs/startup.log; then
        log_success "WiFi startup completed successfully"
        return 0
    else
        log_error "WiFi startup failed"
        return 1
    fi
}

# Function to get WiFi interface from startup script
get_wifi_interface() {
    local interface_file="/app/config/wifi_interface.txt"
    
    if [ -f "$interface_file" ]; then
        local interface
        interface=$(cat "$interface_file")
        if [ -n "$interface" ]; then
            echo "$interface"
            return 0
        fi
    fi
    
    log_error "Could not determine WiFi interface"
    return 1
}

# Function to start roaming script
start_roaming() {
    local wifi_interface="$1"
    
    log_info "Starting WiFi roaming script..."
    log_info "Interface: $wifi_interface"
    log_info "SSID: $SSID_NAME"
    log_info "Time range: ${MIN_TIME} - ${MAX_TIME} minutes"
    log_info "Signal threshold: ${SIGNAL_THRESHOLD} dBm"
    
    # Remove quotes from SSID_NAME for roaming script
    local clean_ssid_name
    clean_ssid_name=$(echo "$SSID_NAME" | sed 's/^"//;s/"$//')
    
    # Start roaming script with logging
    exec /app/scripts/roam.sh \
        "$clean_ssid_name" \
        "$MIN_TIME" \
        "$MAX_TIME" \
        "$SIGNAL_THRESHOLD" \
        "$wifi_interface" \
        2>&1 | tee -a /app/logs/roaming.log
}

# Function to monitor and restart services if needed
monitor_services() {
    local wifi_interface="$1"
    local restart_count=0
    local max_restarts=3
    
    while true; do
        log_info "Monitoring services (restart count: $restart_count/$max_restarts)..."
        
        # Check if wpa_supplicant is still running
        if ! pgrep wpa_supplicant > /dev/null; then
            log_warning "wpa_supplicant process not found"
            
            if [ $restart_count -lt $max_restarts ]; then
                log_info "Attempting to restart wpa_supplicant..."
                if sudo wpa_supplicant -B -i "$wifi_interface" -c /etc/wpa_supplicant/wpa_supplicant.conf -D nl80211,wext; then
                    log_success "wpa_supplicant restarted successfully"
                    ((restart_count++))
                else
                    log_error "Failed to restart wpa_supplicant"
                    break
                fi
            else
                log_error "Maximum restart attempts reached"
                break
            fi
        fi
        
        sleep 30
    done
}

# Main function
main() {
    log_info "WiFi Roaming Container Starting..."
    
    # Display container information
    show_container_info
    
    # Setup logging
    setup_logging
    
    # Start system services
    if ! start_system_services; then
        log_error "Failed to start system services"
        exit 1
    fi
    
    # Run startup script
    if ! run_startup; then
        log_error "Startup script failed"
        exit 1
    fi
    
    # Get WiFi interface
    local wifi_interface
    if ! wifi_interface=$(get_wifi_interface); then
        log_error "Could not determine WiFi interface"
        exit 1
    fi
    
    log_success "Container initialization completed"
    log_info "Starting roaming operation..."
    
    # Start roaming script (this will run indefinitely)
    start_roaming "$wifi_interface" &
    local roaming_pid=$!
    
    # Start service monitor in background
    monitor_services "$wifi_interface" &
    local monitor_pid=$!
    
    # Wait for either process to exit
    wait $roaming_pid $monitor_pid
    
    log_info "Container shutting down..."
}

# Check if running as PID 1 (main container process)
if [ $$ -eq 1 ]; then
    # Running as PID 1, handle signals properly
    main "$@"
else
    # Not PID 1, run directly
    main "$@"
fi
