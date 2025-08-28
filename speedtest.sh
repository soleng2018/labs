#!/bin/bash

# Random Speedtest Script
# Usage: ./speedtest.sh <min_time_minutes> <max_time_minutes> [output_file]

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_speedtest() {
    echo -e "${CYAN}[SPEEDTEST]${NC} $1"
}

# Function to check if speedtest command is available
check_speedtest_availability() {
    if ! command -v speedtest >/dev/null 2>&1; then
        log_error "speedtest command not found!"
        log_error "Please install speedtest-cli:"
        log_error "  Ubuntu/Debian: sudo apt install speedtest-cli"
        log_error "  CentOS/RHEL: sudo yum install speedtest-cli"
        log_error "  Or via pip: pip install speedtest-cli"
        log_error "  Or download from: https://www.speedtest.net/apps/cli"
        return 1
    fi
    return 0
}

# Function to generate random time in minutes
generate_random_time() {
    local min_time="$1"
    local max_time="$2"
    
    # Generate random number between min and max (inclusive)
    echo $((RANDOM % (max_time - min_time + 1) + min_time))
}

# Function to format timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to get current network info
get_network_info() {
    local interface=""
    local ip_addr=""
    
    # Try to get default route interface
    interface=$(ip route | grep default | head -n1 | awk '{print $5}' 2>/dev/null || echo "unknown")
    
    # Get IP address
    if [ "$interface" != "unknown" ]; then
        ip_addr=$(ip addr show "$interface" 2>/dev/null | grep "inet " | head -n1 | awk '{print $2}' | cut -d'/' -f1 || echo "unknown")
    fi
    
    echo "Interface: $interface, IP: $ip_addr"
}

# Function to run speedtest with logging
run_speedtest() {
    local output_file="$1"
    local test_number="$2"
    local timestamp
    timestamp=$(get_timestamp)
    local network_info
    network_info=$(get_network_info)
    
    log_speedtest "Starting speedtest #$test_number at $timestamp"
    log_info "Network: $network_info"
    
    # Prepare log entry
    local log_entry="=== Speedtest #$test_number - $timestamp ===\nNetwork: $network_info\n"
    
    # Run speedtest and capture output
    log_speedtest "Running speedtest command..."
    local speedtest_result
    local speedtest_exit_code=0
    
    # Capture both stdout and stderr, and handle exit codes
    if speedtest_result=$(speedtest 2>&1); then
        log_success "Speedtest completed successfully"
        
        # Extract key metrics from output
        local download_speed=""
        local upload_speed=""
        local ping=""
        local server=""
        
        # Parse results (format may vary by speedtest version)
        download_speed=$(echo "$speedtest_result" | grep -i "download" | head -n1 | grep -oE "[0-9]+\.[0-9]+ Mbps|[0-9]+ Mbps" || echo "N/A")
        upload_speed=$(echo "$speedtest_result" | grep -i "upload" | head -n1 | grep -oE "[0-9]+\.[0-9]+ Mbps|[0-9]+ Mbps" || echo "N/A")
        ping=$(echo "$speedtest_result" | grep -i "ping\|latency" | head -n1 | grep -oE "[0-9]+\.[0-9]+ ms|[0-9]+ ms" || echo "N/A")
        server=$(echo "$speedtest_result" | grep -i "server\|testing from\|hosted by" | head -n1 || echo "N/A")
        
        # Display summary
        log_success "Results Summary:"
        [ "$download_speed" != "N/A" ] && log_success "  Download: $download_speed"
        [ "$upload_speed" != "N/A" ] && log_success "  Upload: $upload_speed"
        [ "$ping" != "N/A" ] && log_success "  Ping: $ping"
        [ "$server" != "N/A" ] && log_info "  Server: $server"
        
    else
        speedtest_exit_code=$?
        log_error "Speedtest failed with exit code $speedtest_exit_code"
        log_error "Error output:"
        echo "$speedtest_result" | while IFS= read -r line; do
            log_error "  $line"
        done
    fi
    
    # Log to file if specified
    if [ -n "$output_file" ]; then
        {
            echo -e "$log_entry"
            echo "Exit Code: $speedtest_exit_code"
            echo "Full Output:"
            echo "$speedtest_result"
            echo ""
            echo "=================================================="
            echo ""
        } >> "$output_file"
        
        if [ $speedtest_exit_code -eq 0 ]; then
            log_info "Results logged to: $output_file"
        else
            log_warning "Error results logged to: $output_file"
        fi
    fi
    
    return $speedtest_exit_code
}

# Function to display script statistics
display_stats() {
    local total_tests="$1"
    local successful_tests="$2"
    local failed_tests="$3"
    local start_time="$4"
    local current_time
    current_time=$(get_timestamp)
    
    log_info "=== Session Statistics ==="
    log_info "Start Time: $start_time"
    log_info "Current Time: $current_time"
    log_info "Total Tests Run: $total_tests"
    log_success "Successful: $successful_tests"
    [ $failed_tests -gt 0 ] && log_error "Failed: $failed_tests" || log_info "Failed: $failed_tests"
    log_info "=========================="
}

# Function to show usage
show_usage() {
    echo "Random Speedtest Script"
    echo "Usage: $0 <min_time_minutes> <max_time_minutes> [output_file]"
    echo ""
    echo "Parameters:"
    echo "  min_time_minutes  - Minimum wait time between speedtests"
    echo "  max_time_minutes  - Maximum wait time between speedtests"
    echo "  output_file       - Optional file to log detailed results"
    echo ""
    echo "Examples:"
    echo "  $0 5 15                    # Run speedtest every 5-15 minutes"
    echo "  $0 10 30 speedtest.log     # Log results to speedtest.log"
    echo "  $0 1 5 /tmp/network.log    # Frequent testing with logging"
    echo ""
    echo "Note: Press Ctrl+C to stop the script gracefully"
}

# Main function
main() {
    # Check arguments
    if [ $# -lt 2 ] || [ $# -gt 3 ]; then
        show_usage
        exit 1
    fi
    
    local min_time="$1"
    local max_time="$2"
    local output_file="${3:-}"
    
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
    
    # Validate output file if specified
    if [ -n "$output_file" ]; then
        # Try to create/write to the output file
        if ! touch "$output_file" 2>/dev/null; then
            log_error "Cannot write to output file: $output_file"
            exit 1
        fi
        log_info "Results will be logged to: $output_file"
    fi
    
    # Check if speedtest is available
    if ! check_speedtest_availability; then
        exit 1
    fi
    
    # Test speedtest command
    log_info "Testing speedtest command availability..."
    if timeout 10 speedtest --version >/dev/null 2>&1 || timeout 10 speedtest --help >/dev/null 2>&1; then
        log_success "speedtest command is working"
    else
        log_warning "Could not verify speedtest command, but proceeding anyway"
    fi
    
    # Display configuration
    log_info "Starting Random Speedtest Script"
    log_info "Time range: $min_time - $max_time minutes"
    [ -n "$output_file" ] && log_info "Output file: $output_file"
    log_info "Network info: $(get_network_info)"
    log_info ""
    log_info "Press Ctrl+C to stop the script gracefully"
    echo ""
    
    # Initialize counters
    local test_count=0
    local successful_tests=0
    local failed_tests=0
    local start_time
    start_time=$(get_timestamp)
    
    # Write header to log file if specified
    if [ -n "$output_file" ]; then
        {
            echo "Random Speedtest Log"
            echo "Started: $start_time"
            echo "Time Range: $min_time - $max_time minutes"
            echo "Network: $(get_network_info)"
            echo "=================================================="
            echo ""
        } > "$output_file"
    fi
    
    # Main loop
    while true; do
        # Increment test counter
        ((test_count++))
        
        # Generate random wait time
        local wait_time
        wait_time=$(generate_random_time "$min_time" "$max_time")
        
        # Display status
        if [ $test_count -eq 1 ]; then
            log_info "Running first speedtest immediately..."
        else
            log_info "Next speedtest in $wait_time minutes..."
            
            # Wait with periodic updates
            local wait_seconds=$((wait_time * 60))
            local elapsed=0
            local update_interval=60  # Update every minute
            
            while [ $elapsed -lt $wait_seconds ]; do
                local remaining=$((wait_seconds - elapsed))
                if [ $((elapsed % update_interval)) -eq 0 ] && [ $elapsed -gt 0 ]; then
                    local remaining_minutes=$(((remaining + 59) / 60))
                    log_info "Still waiting... $remaining_minutes minutes remaining"
                fi
                sleep 60
                elapsed=$((elapsed + 60))
            done
        fi
        
        # Run speedtest
        echo ""
        if run_speedtest "$output_file" "$test_count"; then
            ((successful_tests++))
        else
            ((failed_tests++))
        fi
        
        # Display statistics every 5 tests
        if [ $((test_count % 5)) -eq 0 ]; then
            echo ""
            display_stats "$test_count" "$successful_tests" "$failed_tests" "$start_time"
        fi
        
        echo ""
        log_info "Completed test $test_count. Next test scheduled in $min_time-$max_time minutes."
        echo ""
        
        # Brief pause before next cycle
        sleep 5
    done
}

# Handle Ctrl+C gracefully
cleanup() {
    local exit_code=$?
    echo ""
    log_warning "Script interrupted by user"
    
    # Show final statistics if we ran any tests
    if [ -n "${test_count:-}" ] && [ "${test_count:-0}" -gt 0 ]; then
        echo ""
        display_stats "${test_count:-0}" "${successful_tests:-0}" "${failed_tests:-0}" "${start_time:-$(get_timestamp)}"
    fi
    
    log_info "Exiting gracefully..."
    exit $exit_code
}

trap cleanup INT TERM

# Run main function with all arguments
main "$@"