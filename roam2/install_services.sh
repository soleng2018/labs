#!/bin/bash

# WiFi Roaming Services Installation Script
# This script installs roam.sh and speedtest.sh as systemd services

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
LOG_DIR="/var/log"

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

print_status "Installing WiFi Roaming Services..."

# Create installation directory
print_status "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Copy files to installation directory
print_status "Copying files to $INSTALL_DIR"
cp roam.sh "$INSTALL_DIR/"
cp speedtest.sh "$INSTALL_DIR/"
cp parameters.txt "$INSTALL_DIR/"
cp wpa_supplicant.conf "$INSTALL_DIR/"
cp configure_wpa.sh "$INSTALL_DIR/"
cp wpa_supplicant_wrapper.sh "$INSTALL_DIR/"

# Make scripts executable
chmod +x "$INSTALL_DIR/roam.sh"
chmod +x "$INSTALL_DIR/speedtest.sh"
chmod +x "$INSTALL_DIR/configure_wpa.sh"
chmod +x "$INSTALL_DIR/wpa_supplicant_wrapper.sh"

# Update file paths in scripts to use /opt/roam/
print_status "Updating file paths in scripts..."

# Update roam.sh
sed -i 's|SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" \&\& pwd)"|SCRIPT_DIR="/opt/roam"|g' "$INSTALL_DIR/roam.sh"
sed -i 's|PARAMETERS_FILE="\$SCRIPT_DIR/parameters.txt"|PARAMETERS_FILE="/opt/roam/parameters.txt"|g' "$INSTALL_DIR/roam.sh"

# Update speedtest.sh
sed -i 's|SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" \&\& pwd)"|SCRIPT_DIR="/opt/roam"|g' "$INSTALL_DIR/speedtest.sh"
sed -i 's|PARAMETERS_FILE="\$SCRIPT_DIR/parameters.txt"|PARAMETERS_FILE="/opt/roam/parameters.txt"|g' "$INSTALL_DIR/speedtest.sh"

# Update configure_wpa.sh
sed -i 's|SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" \&\& pwd)"|SCRIPT_DIR="/opt/roam"|g' "$INSTALL_DIR/configure_wpa.sh"
sed -i 's|PARAMETERS_FILE="\$SCRIPT_DIR/parameters.txt"|PARAMETERS_FILE="/opt/roam/parameters.txt"|g' "$INSTALL_DIR/configure_wpa.sh"

# Copy service files
print_status "Installing systemd service files..."
cp roam.service "$SERVICE_DIR/"
cp speedtest.service "$SERVICE_DIR/"
cp wpa_supplicant.service "$SERVICE_DIR/"

# Set proper permissions
chmod 644 "$SERVICE_DIR/roam.service"
chmod 644 "$SERVICE_DIR/speedtest.service"
chmod 644 "$SERVICE_DIR/wpa_supplicant.service"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Reload systemd daemon
print_status "Reloading systemd daemon..."
systemctl daemon-reload

# Configure wpa_supplicant before enabling services
print_status "Configuring wpa_supplicant..."
if [[ -f "$INSTALL_DIR/configure_wpa.sh" ]]; then
    "$INSTALL_DIR/configure_wpa.sh"
else
    print_warning "configure_wpa.sh not found, skipping wpa_supplicant configuration"
fi

# Enable services
print_status "Enabling services..."
systemctl enable wpa_supplicant.service
systemctl enable roam.service
systemctl enable speedtest.service

print_success "Installation completed successfully!"
print_status ""
print_status "Services installed:"
print_status "  - wpa_supplicant.service (WiFi Authentication)"
print_status "  - roam.service (WiFi Roaming)"
print_status "  - speedtest.service (WiFi Speed Testing)"
print_status ""
print_status "Service management commands:"
print_status "  Start services:"
print_status "    sudo systemctl start wpa_supplicant.service"
print_status "    sudo systemctl start roam.service"
print_status "    sudo systemctl start speedtest.service"
print_status ""
print_status "  Stop services:"
print_status "    sudo systemctl stop wpa_supplicant.service"
print_status "    sudo systemctl stop roam.service"
print_status "    sudo systemctl stop speedtest.service"
print_status ""
print_status "  Check status:"
print_status "    sudo systemctl status wpa_supplicant.service"
print_status "    sudo systemctl status roam.service"
print_status "    sudo systemctl status speedtest.service"
print_status ""
print_status "  View logs:"
print_status "    sudo journalctl -u wpa_supplicant.service -f"
print_status "    sudo journalctl -u roam.service -f"
print_status "    sudo journalctl -u speedtest.service -f"
print_status ""
print_status "  Disable services:"
print_status "    sudo systemctl disable wpa_supplicant.service"
print_status "    sudo systemctl disable roam.service"
print_status "    sudo systemctl disable speedtest.service"
print_status ""
print_warning "Note: Services will start automatically on boot."
print_warning "Make sure to configure parameters.txt before starting services."
print_status ""
print_status "Configuration file location: $INSTALL_DIR/parameters.txt"
print_status "Log file location: $LOG_DIR/roam_debug.log"
