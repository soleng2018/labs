#!/bin/bash

# Speedtest Script
# This script runs speed tests at random intervals based on parameters

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARAMETERS_FILE="$SCRIPT_DIR/parameters.txt"
LOG_FILE="/var/log/speedtest_debug.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE" > /dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Load parameters from file
load_parameters() {
    if [[ ! -f "$PARAMETERS_FILE" ]]; then
        error_exit "Parameters file not found: $PARAMETERS_FILE"
    fi
    
    log "Loading parameters from $PARAMETERS_FILE"
    
    # Source the parameters file
    source "$PARAMETERS_FILE"
    
    # Validate speedtest parameters
    if ! [[ "$Min_Time_Speedtest" =~ ^[0-9]+$ ]]; then
        error_exit "Min_Time_Speedtest must be an integer"
    fi
    
    if ! [[ "$Max_Time_Speedtest" =~ ^[0-9]+$ ]]; then
        error_exit "Max_Time_Speedtest must be an integer"
    fi
    
    if [[ $Min_Time_Speedtest -gt $Max_Time_Speedtest ]]; then
        error_exit "Min_Time_Speedtest cannot be greater than Max_Time_Speedtest"
    fi
    
    log "Speedtest parameters loaded successfully:"
    log "  Speedtest interval: $Min_Time_Speedtest-$Max_Time_Speedtest minutes"
}

# Check if speedtest-cli is installed
check_speedtest_cli() {
    log "Checking if speedtest-cli is installed..."
    
    if ! command -v speedtest-cli >/dev/null 2>&1; then
        log "speedtest-cli not found, attempting to install..."
        
        # Try to install speedtest-cli
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y speedtest-cli
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y speedtest-cli
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y speedtest-cli
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm speedtest-cli
        elif command -v zypper >/dev/null 2>&1; then
            sudo zypper install -y speedtest-cli
        else
            error_exit "Cannot install speedtest-cli automatically. Please install it manually."
        fi
        
        # Verify installation
        if ! command -v speedtest-cli >/dev/null 2>&1; then
            error_exit "Failed to install speedtest-cli"
        fi
    fi
    
    log "speedtest-cli is available"
}

# Run speedtest
run_speedtest() {
    log "Running speedtest..."
    
    # Create temporary file for speedtest output
    local temp_file=$(mktemp)
    
    # Run speedtest and capture output
    if speedtest-cli --simple > "$temp_file" 2>&1; then
        log "Speedtest completed successfully:"
        while IFS= read -r line; do
            log "  $line"
        done < "$temp_file"
    else
        log "Speedtest failed, output:"
        while IFS= read -r line; do
            log "  $line"
        done < "$temp_file"
    fi
    
    # Clean up temporary file
    rm -f "$temp_file"
}

# Get random time between min and max
get_random_time() {
    local min="$1"
    local max="$2"
    echo $((RANDOM % (max - min + 1) + min))
}

# Main speedtest loop
speedtest_loop() {
    log "Starting speedtest loop..."
    
    while true; do
        # Run speedtest
        run_speedtest
        
        # Wait for random time before next speedtest
        local wait_time=$(get_random_time "$Min_Time_Speedtest" "$Max_Time_Speedtest")
        log "Waiting $wait_time minutes before next speedtest..."
        sleep $((wait_time * 60))
    done
}

# Main function
main() {
    log "Starting speedtest script"
    
    # Check if running as root for log file access
    if [[ $EUID -ne 0 ]]; then
        log "This script requires root privileges for logging"
        log "Please run with sudo"
        exit 1
    fi
    
    # Load parameters
    load_parameters
    
    # Check speedtest-cli installation
    check_speedtest_cli
    
    # Start speedtest loop
    speedtest_loop
}

# Run main function
main "$@"

