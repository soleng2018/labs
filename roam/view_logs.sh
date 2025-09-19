#!/bin/bash

# WiFi Roaming Log Viewer
# This script provides easy access to view roaming and speedtest logs

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log directory
LOG_DIR="/var/log/wifi-roam"

# Function to display usage
show_usage() {
    echo "WiFi Roaming Log Viewer"
    echo ""
    echo "Usage: $0 [OPTION] [LOG_TYPE]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --follow   Follow log output in real-time"
    echo "  -t, --tail     Show last N lines (default: 50)"
    echo "  -a, --all      Show all log content"
    echo ""
    echo "Log Types:"
    echo "  roaming        Show roaming events log"
    echo "  roaming-debug  Show roaming debug log"
    echo "  speedtest      Show speedtest events log"
    echo "  speedtest-debug Show speedtest debug log"
    echo "  all            Show all logs (default)"
    echo ""
    echo "Examples:"
    echo "  $0                              # Show all logs"
    echo "  $0 roaming                      # Show roaming events"
    echo "  $0 -f speedtest                 # Follow speedtest log in real-time"
    echo "  $0 -t 100 roaming               # Show last 100 lines of roaming log"
    echo "  $0 -a speedtest-debug           # Show all speedtest debug content"
}

# Function to check if log files exist
check_log_files() {
    local missing_files=()
    
    for log_type in roaming roaming-debug speedtest speedtest-debug; do
        if [ ! -f "$LOG_DIR/${log_type}.log" ]; then
            missing_files+=("${log_type}.log")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        echo -e "${YELLOW}[WARNING]${NC} Missing log files:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        echo ""
    fi
}

# Function to display log content
display_log() {
    local log_file="$1"
    local follow="$2"
    local tail_lines="$3"
    local show_all="$4"
    
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}[ERROR]${NC} Log file not found: $log_file"
        return 1
    fi
    
    echo -e "${BLUE}[INFO]${NC} Displaying: $(basename "$log_file")"
    echo "=========================================="
    
    if [ "$follow" = true ]; then
        tail -f "$log_file"
    elif [ "$show_all" = true ]; then
        cat "$log_file"
    else
        tail -n "$tail_lines" "$log_file"
    fi
}

# Function to display all logs
display_all_logs() {
    local follow="$1"
    local tail_lines="$2"
    local show_all="$3"
    
    for log_type in roaming roaming-debug speedtest speedtest-debug; do
        local log_file="$LOG_DIR/${log_type}.log"
        if [ -f "$log_file" ]; then
            display_log "$log_file" "$follow" "$tail_lines" "$show_all"
            echo ""
            echo "=========================================="
            echo ""
        fi
    done
}

# Main function
main() {
    local follow=false
    local tail_lines=50
    local show_all=false
    local log_type="all"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -f|--follow)
                follow=true
                shift
                ;;
            -t|--tail)
                if [[ $2 =~ ^[0-9]+$ ]]; then
                    tail_lines="$2"
                    shift 2
                else
                    echo -e "${RED}[ERROR]${NC} Tail value must be a number"
                    exit 1
                fi
                ;;
            -a|--all)
                show_all=true
                shift
                ;;
            roaming|roaming-debug|speedtest|speedtest-debug|all)
                log_type="$1"
                shift
                ;;
            *)
                echo -e "${RED}[ERROR]${NC} Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check if log directory exists
    if [ ! -d "$LOG_DIR" ]; then
        echo -e "${RED}[ERROR]${NC} Log directory not found: $LOG_DIR"
        echo "Make sure the WiFi roaming services are running."
        exit 1
    fi
    
    # Check for missing log files
    check_log_files
    
    # Display logs based on type
    if [ "$log_type" = "all" ]; then
        display_all_logs "$follow" "$tail_lines" "$show_all"
    else
        local log_file="$LOG_DIR/${log_type}.log"
        display_log "$log_file" "$follow" "$tail_lines" "$show_all"
    fi
}

# Run main function with all arguments
main "$@"

