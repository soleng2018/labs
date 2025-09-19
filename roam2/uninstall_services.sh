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
systemctl stop roam.service 2>/dev/null || true
systemctl stop speedtest.service 2>/dev/null || true

# Disable services
print_status "Disabling services..."
systemctl disable roam.service 2>/dev/null || true
systemctl disable speedtest.service 2>/dev/null || true

# Remove service files
print_status "Removing systemd service files..."
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
if [[ -f "/var/log/roam_debug.log" ]]; then
    print_warning "Log file /var/log/roam_debug.log still exists."
    read -p "Do you want to remove it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Removing log file..."
        rm -f "/var/log/roam_debug.log"
        print_success "Log file removed."
    else
        print_status "Log file preserved at /var/log/roam_debug.log"
    fi
fi

print_success "Uninstallation completed successfully!"
print_status ""
print_status "Services have been stopped, disabled, and removed."
print_status "The systemd service files have been removed."
print_status ""
print_warning "Note: If you modified any configuration files, they may still exist."
print_status "Check $INSTALL_DIR for any remaining files."
