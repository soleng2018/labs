#!/bin/bash

# WPA Supplicant Configuration Script
# This script configures wpa_supplicant.conf based on parameters.txt

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARAMETERS_FILE="$SCRIPT_DIR/parameters.txt"
WPA_CONF_FILE="$SCRIPT_DIR/wpa_supplicant.conf"
WPA_CONF_TEMPLATE="$SCRIPT_DIR/wpa_supplicant.conf.template"

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

# Load parameters from file
load_parameters() {
    if [[ ! -f "$PARAMETERS_FILE" ]]; then
        print_error "Parameters file not found: $PARAMETERS_FILE"
        exit 1
    fi
    
    print_status "Loading parameters from $PARAMETERS_FILE"
    source "$PARAMETERS_FILE"
    
    # Validate required parameters
    if [[ -z "$SSID_Name" ]]; then
        print_error "SSID_Name not defined in parameters.txt"
        exit 1
    fi
    
    if [[ -z "$EAP_Username" ]]; then
        print_error "EAP_Username not defined in parameters.txt"
        exit 1
    fi
    
    if [[ -z "$EAP_Password" ]]; then
        print_error "EAP_Password not defined in parameters.txt"
        exit 1
    fi
    
    print_success "Parameters loaded successfully"
}

# Create wpa_supplicant.conf from template
configure_wpa_supplicant() {
    print_status "Configuring wpa_supplicant.conf..."
    
    # Create backup of existing config
    if [[ -f "$WPA_CONF_FILE" ]]; then
        cp "$WPA_CONF_FILE" "${WPA_CONF_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        print_status "Backup created: ${WPA_CONF_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Create the wpa_supplicant.conf file
    cat > "$WPA_CONF_FILE" << EOF
# Global settings for better roaming
fast_reauth=$Fast_Reauth
pmf=$PMF
ctrl_interface=/run/wpa_supplicant
ctrl_interface_group=netdev
update_config=$Update_Config
country=$Country_Code
freq_list=
scan_cur_freq=$Scan_Cur_Freq

# Network configuration for EAP-PEAP MSCHAPv2
network={
    # Network SSID
    ssid="$SSID_Name"

    # Key management - WPA-EAP for enterprise networks
    key_mgmt=WPA-EAP

    # EAP method - PEAP (Protected EAP)
    eap=PEAP

    # Your username/identity
    identity="$EAP_Username"

    # Your password
    password="$EAP_Password"

    # Phase 2 authentication method - MSCHAPv2
    phase2="auth=MSCHAPV2"

    # Certificate validation settings
EOF

    # Add certificate validation settings based on configuration
    if [[ "$Disable_Cert_Validation" == "1" ]]; then
        print_warning "Certificate validation is DISABLED - this is insecure!"
        cat >> "$WPA_CONF_FILE" << EOF
    # DISABLE certificate validation (insecure but sometimes required)
    # WARNING: This makes the connection vulnerable to man-in-the-middle attacks
    phase1="peaplabel=0"
EOF
    else
        print_status "Certificate validation is ENABLED (recommended)"
        cat >> "$WPA_CONF_FILE" << EOF
    # Certificate validation enabled (recommended for security)
    # phase1="peaplabel=0"  # Commented out for security
EOF
    fi
    
    cat >> "$WPA_CONF_FILE" << EOF

    # Priority for this network (higher = preferred)
    priority=$Network_Priority
}
EOF

    print_success "wpa_supplicant.conf configured successfully"
}

# Set proper permissions
set_permissions() {
    print_status "Setting proper permissions..."
    
    # Set restrictive permissions on wpa_supplicant.conf (contains password)
    chmod 600 "$WPA_CONF_FILE"
    chown root:root "$WPA_CONF_FILE"
    
    print_success "Permissions set successfully"
}

# Main function
main() {
    print_status "Starting WPA Supplicant configuration..."
    
    # Check if running as root for file permissions
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges for file permissions"
        print_status "Please run with sudo"
        exit 1
    fi
    
    # Load parameters
    load_parameters
    
    # Configure wpa_supplicant
    configure_wpa_supplicant
    
    # Set permissions
    set_permissions
    
    print_success "WPA Supplicant configuration completed!"
    print_status ""
    print_status "Configuration summary:"
    print_status "  SSID: $SSID_Name"
    print_status "  Username: $EAP_Username"
    print_status "  Country: $Country_Code"
    print_status "  Certificate validation: $([ "$Disable_Cert_Validation" == "1" ] && echo "DISABLED (insecure)" || echo "ENABLED (secure)")"
    print_status "  Config file: $WPA_CONF_FILE"
    print_status ""
    print_warning "Note: The wpa_supplicant.conf file contains your password in plain text."
    print_warning "Make sure to keep this file secure and never share it."
}

# Run main function
main "$@"
