#!/bin/bash

# WiFi Roaming Services Uninstallation Script
# This script removes the systemd services and files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/roam"
SERVICE_DIR="/etc/systemd/system"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_status "Uninstalling WiFi Roaming Services..."

# Stop services if running
print_status "Stopping services..."
systemctl stop wpa_supplicant.service 2>/dev/null || true
systemctl stop roam.service 2>/dev/null || true
systemctl stop speedtest.service 2>/dev/null || true

# Disable services
print_status "Disabling services..."
systemctl disable wpa_supplicant.service 2>/dev/null || true
systemctl disable roam.service 2>/dev/null || true
systemctl disable speedtest.service 2>/dev/null || true

# Remove service files
print_status "Removing systemd service files..."
rm -f "$SERVICE_DIR/wpa_supplicant.service"
rm -f "$SERVICE_DIR/roam.service"
rm -f "$SERVICE_DIR/speedtest.service"

# Reload systemd daemon
print_status "Reloading systemd daemon..."
systemctl daemon-reload

# Ask user if they want to remove installation directory
if [[ -d "$INSTALL_DIR" ]]; then
    print_warning "Installation directory $INSTALL_DIR still exists."
    read -p "Do you want to remove it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Removing installation directory..."
        rm -rf "$INSTALL_DIR"
        print_success "Installation directory removed."
    else
        print_status "Installation directory preserved at $INSTALL_DIR"
    fi
fi

# Ask user if they want to remove log files
print_status "Checking for log files..."
log_files_removed=false

# Check for roam debug log
if [[ -f "/var/log/roam_debug.log" ]]; then
    print_warning "Log file /var/log/roam_debug.log still exists."
    read -p "Do you want to remove it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Removing roam debug log..."
        rm -f "/var/log/roam_debug.log"
        log_files_removed=true
        print_success "Roam debug log removed."
    else
        print_status "Roam debug log preserved at /var/log/roam_debug.log"
    fi
fi

# Check for wpa_supplicant log
if [[ -f "/var/log/wpa_supplicant.log" ]]; then
    print_warning "Log file /var/log/wpa_supplicant.log still exists."
    read -p "Do you want to remove it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Removing wpa_supplicant log..."
        rm -f "/var/log/wpa_supplicant.log"
        log_files_removed=true
        print_success "WPA supplicant log removed."
    else
        print_status "WPA supplicant log preserved at /var/log/wpa_supplicant.log"
    fi
fi

# Check for speedtest log
if [[ -f "/var/log/speedtest_debug.log" ]]; then
    print_warning "Log file /var/log/speedtest_debug.log still exists."
    read -p "Do you want to remove it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Removing speedtest log..."
        rm -f "/var/log/speedtest_debug.log"
        log_files_removed=true
        print_success "Speedtest log removed."
    else
        print_status "Speedtest log preserved at /var/log/speedtest_debug.log"
    fi
fi

if [[ "$log_files_removed" == "false" ]]; then
    print_status "No log files found or all preserved."
fi

print_success "Uninstallation completed successfully!"
print_status ""
print_status "Services have been stopped, disabled, and removed."
print_status "The systemd service files have been removed."
print_status ""
print_warning "Note: If you modified any configuration files, they may still exist."
print_status "Check $INSTALL_DIR for any remaining files."
