#!/bin/bash

# Script to switch from CDROM repositories to internet repositories
# This can be run manually after WiFi is connected

set -euo pipefail

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

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        log_info "Please run: sudo $0"
        exit 1
    fi
}

# Function to test internet connectivity
test_internet_connectivity() {
    local test_sites=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    
    log_info "Testing internet connectivity..."
    
    for site in "${test_sites[@]}"; do
        if ping -c 1 -W 3 "$site" >/dev/null 2>&1; then
            log_success "Internet connectivity confirmed (reached $site)"
            return 0
        fi
    done
    
    # Try DNS resolution as well
    if nslookup archive.ubuntu.com >/dev/null 2>&1; then
        log_success "Internet connectivity confirmed (DNS resolution works)"
        return 0
    fi
    
    log_error "No internet connectivity detected"
    return 1
}

# Function to backup sources.list
backup_sources_list() {
    local backup_file="/etc/apt/sources.list.backup.$(date +%s)"
    
    if [ -f "/etc/apt/sources.list" ]; then
        cp /etc/apt/sources.list "$backup_file"
        log_success "Backed up sources.list to: $backup_file"
    else
        log_warning "No existing sources.list found"
    fi
}

# Function to remove CDROM sources
remove_cdrom_sources() {
    log_info "Removing CDROM sources..."
    
    # Count existing CDROM entries
    local cdrom_count
    cdrom_count=$(grep -c "^deb cdrom:" /etc/apt/sources.list 2>/dev/null || echo "0")
    
    if [ "$cdrom_count" -eq 0 ]; then
        log_info "No CDROM sources found to remove"
        return 0
    fi
    
    log_info "Found $cdrom_count CDROM source(s) to remove"
    
    # Show what we're removing
    log_info "CDROM sources being removed:"
    grep "^deb cdrom:" /etc/apt/sources.list 2>/dev/null | sed 's/^/  /' || true
    
    # Remove CDROM sources
    sed -i '/^deb cdrom:/d' /etc/apt/sources.list
    sed -i '/^deb-src cdrom:/d' /etc/apt/sources.list
    
    # Also remove commented CDROM sources to clean up
    sed -i '/^# deb cdrom:/d' /etc/apt/sources.list
    
    log_success "CDROM sources removed"
}

# Function to add internet repositories
add_internet_repositories() {
    log_info "Adding Ubuntu internet repositories..."
    
    # Check if internet repositories already exist
    if grep -q "deb http://archive.ubuntu.com/ubuntu" /etc/apt/sources.list 2>/dev/null; then
        log_info "Internet repositories already present"
        return 0
    fi
    
    # Add standard Ubuntu repositories
    cat >> /etc/apt/sources.list << 'EOF'

# Ubuntu internet repositories (added by switch-to-internet-repos.sh)
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse

# Source packages (uncomment if needed)
# deb-src http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
# deb-src http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
# deb-src http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse
# deb-src http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
EOF
    
    log_success "Internet repositories added"
}

# Function to update package list
update_package_list() {
    log_info "Updating package list..."
    
    if apt-get update; then
        log_success "Package list updated successfully"
        return 0
    else
        log_error "Failed to update package list"
        return 1
    fi
}

# Function to show current sources
show_sources() {
    log_info "Current APT sources:"
    echo "===================="
    
    if [ -f "/etc/apt/sources.list" ]; then
        # Show active (non-commented) sources
        grep "^deb" /etc/apt/sources.list | sed 's/^/  /'
    else
        log_error "No sources.list file found"
    fi
    
    echo "===================="
}

# Main function
main() {
    log_info "Ubuntu Repository Switcher - CDROM to Internet"
    log_info "==============================================="
    
    # Check if running as root
    check_root
    
    # Show current sources first
    echo ""
    log_info "BEFORE - Current repository sources:"
    show_sources
    
    # Test internet connectivity
    echo ""
    if ! test_internet_connectivity; then
        log_error "Cannot switch to internet repositories without internet access"
        log_info "Please ensure WiFi/network is connected and try again"
        exit 1
    fi
    
    # Backup current sources.list
    echo ""
    backup_sources_list
    
    # Remove CDROM sources
    echo ""
    remove_cdrom_sources
    
    # Add internet repositories  
    echo ""
    add_internet_repositories
    
    # Update package list
    echo ""
    if update_package_list; then
        echo ""
        log_success "Repository switch completed successfully!"
        
        # Show final sources
        echo ""
        log_info "AFTER - Updated repository sources:"
        show_sources
        
        echo ""
        log_info "You can now use 'apt-get install' to install packages from the internet"
        log_info "Example: sudo apt-get install vim curl wget"
    else
        log_error "Repository switch completed but package list update failed"
        log_info "You may need to check your internet connection and run 'sudo apt-get update' manually"
        exit 1
    fi
}

# Handle help
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Ubuntu Repository Switcher - CDROM to Internet"
    echo ""
    echo "Usage: $0"
    echo ""
    echo "This script will:"
    echo "  1. Test internet connectivity"
    echo "  2. Backup current sources.list"
    echo "  3. Remove CDROM repository sources"
    echo "  4. Add Ubuntu internet repositories"
    echo "  5. Update package list"
    echo ""
    echo "Run this after installation when internet/WiFi is connected"
    echo "to switch from CDROM sources to internet repositories."
    exit 0
fi

# Run main function
main "$@"
