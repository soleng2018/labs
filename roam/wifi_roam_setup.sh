#!/bin/bash

# WiFi Setup Script for EAP-PEAP MSCHAPv2 with Roaming
# This script sets up wpa_supplicant configuration and enables the roaming service

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

# Function to load parameters from file
load_parameters() {
    local params_file="$1"

    if [ ! -f "$params_file" ]; then
        log_error "Parameters file '$params_file' not found"
        exit 1
    fi

    log_info "Loading parameters from $params_file"

    # Source the parameters file
    source "$params_file"

    # Validate required parameters
    if [ -z "${SSID:-}" ]; then
        log_error "SSID not defined in parameters file"
        exit 1
    fi

    if [ -z "${USERNAME:-}" ]; then
        log_error "USERNAME not defined in parameters file"
        exit 1
    fi

    if [ -z "${PASSWORD:-}" ]; then
        log_error "PASSWORD not defined in parameters file"
        exit 1
    fi

    # Set defaults for optional parameters
    MIN_TIME="${MIN_TIME:-10}"
    MAX_TIME="${MAX_TIME:-20}"
    MIN_SIGNAL="${MIN_SIGNAL:--75}"
    SPEEDTEST_MIN_TIME="${SPEEDTEST_MIN_TIME:-30}"
    SPEEDTEST_MAX_TIME="${SPEEDTEST_MAX_TIME:-120}"
    INTERFACE="${INTERFACE:-}"

    log_success "Parameters loaded successfully"
    log_info "SSID: $SSID"
    log_info "Username: $USERNAME"
    log_info "Min Time: $MIN_TIME minutes"
    log_info "Max Time: $MAX_TIME minutes"
    log_info "Min Signal: $MIN_SIGNAL dBm"
    log_info "Speedtest Min Time: $SPEEDTEST_MIN_TIME minutes"
    log_info "Speedtest Max Time: $SPEEDTEST_MAX_TIME minutes"

    if [ -n "$INTERFACE" ]; then
        log_info "Interface: $INTERFACE (specified)"
    else
        log_info "Interface: auto-detect"
    fi
}

# Function to install required packages
install_packages() {
    log_info "Checking for required packages..."
    
    # Check if packages are already installed
    local packages_missing=()
    local required_packages=("wpasupplicant" "dhcpcd5" "iw" "wireless-tools")
    
    for package in "${required_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$package"; then
            packages_missing+=("$package")
        fi
    done
    
    if [ ${#packages_missing[@]} -eq 0 ]; then
        log_success "All required packages are already installed"
        return 0
    fi
    
    log_info "Missing packages: ${packages_missing[*]}"
    log_info "Attempting to install required packages..."

    # Check if we have internet connectivity
    local has_internet=false
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        has_internet=true
        log_success "Internet connectivity detected"
    else
        log_warning "No internet connectivity - will use CDROM sources if available"
    fi

    # If we have internet, switch from CDROM to online repositories
    if [ "$has_internet" = true ] && grep -q "deb cdrom:" /etc/apt/sources.list 2>/dev/null; then
        log_info "Switching from CDROM to internet repositories..."
        
        # Backup original sources.list
        cp /etc/apt/sources.list /etc/apt/sources.list.backup
        
        # Remove CDROM sources and add internet repositories
        sed -i '/deb cdrom:/d' /etc/apt/sources.list
        
        # Ensure we have proper Ubuntu repositories
        if ! grep -q "deb http://archive.ubuntu.com/ubuntu" /etc/apt/sources.list; then
            log_info "Adding Ubuntu internet repositories..."
            cat >> /etc/apt/sources.list << 'EOF'

# Ubuntu repositories
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
EOF
        fi
        
        log_success "Switched to internet repositories"
    fi

    # Try to update package list
    if apt-get update 2>/dev/null; then
        log_success "Package list updated"
    else
        log_warning "Failed to update package list"
        if [ "$has_internet" = false ]; then
            log_info "This is expected without internet connectivity"
        fi
    fi

    # Try to install required packages
    if apt-get install -y wpasupplicant dhcpcd5 iw wireless-tools 2>/dev/null; then
        log_success "Required packages installed successfully"
        return 0
    else
        log_warning "Failed to install packages via apt-get"
        
        # Check if packages are actually available in the system
        local critical_missing=()
        for package in "${required_packages[@]}"; do
            if ! command -v "${package}" >/dev/null 2>&1 && ! dpkg -l | grep -q "^ii.*${package}"; then
                critical_missing+=("$package")
            fi
        done
        
        if [ ${#critical_missing[@]} -eq 0 ]; then
            log_success "Required packages appear to be available despite installation failure"
            return 0
        else
            log_error "Critical packages are missing: ${critical_missing[*]}"
            log_error "This may cause WiFi setup to fail"
            log_warning "Continuing with setup anyway (packages might be pre-installed in custom ISO)"
            return 0  # Don't fail the entire setup
        fi
    fi
}

# Function to disable conflicting services
disable_conflicting_services() {
    log_info "Disabling conflicting network services..."

    # Stop and disable NetworkManager if present
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        log_info "Stopping NetworkManager..."
        systemctl stop NetworkManager
        systemctl disable NetworkManager
        log_success "NetworkManager disabled"
    fi

    # Stop and disable systemd-networkd if present
    if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        log_info "Stopping systemd-networkd..."
        systemctl stop systemd-networkd
        systemctl disable systemd-networkd
        log_success "systemd-networkd disabled"
    fi

    # Stop and disable dhcpcd if running (we'll start it manually later)
    if systemctl is-active --quiet dhcpcd 2>/dev/null; then
        log_info "Stopping dhcpcd service..."
        systemctl stop dhcpcd
        systemctl disable dhcpcd
        log_success "dhcpcd service disabled (will be managed manually)"
    fi
}

# Function to configure wpa_supplicant.conf
configure_wpa_supplicant() {
    local wpa_conf="/etc/wpa_supplicant/wpa_supplicant.conf"
    local template_conf="./wpa_supplicant.conf"

    log_info "Configuring wpa_supplicant.conf..."

    # Check if template exists
    if [ ! -f "$template_conf" ]; then
        log_error "Template wpa_supplicant.conf not found in current directory"
        exit 1
    fi

    # Create backup of existing config if it exists
    if [ -f "$wpa_conf" ]; then
        cp "$wpa_conf" "$wpa_conf.backup.$(date +%s)"
        log_info "Backup created: $wpa_conf.backup.$(date +%s)"
    fi

    # Create wpa_supplicant directory if it doesn't exist
    mkdir -p /etc/wpa_supplicant

    # Copy template and replace placeholders
    cp "$template_conf" "$wpa_conf"

    # Replace placeholders with actual values
    sed -i "s/SSID_PLACEHOLDER/$SSID/g" "$wpa_conf"
    sed -i "s/USERNAME_PLACEHOLDER/$USERNAME/g" "$wpa_conf"
    sed -i "s/PASSWORD_PLACEHOLDER/$PASSWORD/g" "$wpa_conf"

    # Set proper permissions
    chmod 600 "$wpa_conf"
    chown root:root "$wpa_conf"

    log_success "wpa_supplicant.conf configured at $wpa_conf"
}

# Function to create systemd service for wifi roaming
create_roaming_service() {
    local service_file="/etc/systemd/system/wifi-roaming.service"
    local script_dir="/opt/wifi-roam"

    log_info "Creating systemd service for WiFi roaming..."

    # Create the service file
    cat > "$service_file" << EOF
[Unit]
Description=WiFi Auto Roaming Service
After=network-online.target wpa_supplicant.service
Wants=network-online.target
Requires=wpa_supplicant.service

[Service]
Type=simple
ExecStart=$script_dir/roam_script.sh $SSID $MIN_TIME $MAX_TIME $MIN_SIGNAL
Restart=always
RestartSec=30
RestartPreventExitStatus=2
User=root
WorkingDirectory=$script_dir
StandardOutput=journal
StandardError=journal
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

    # Set proper permissions
    chmod 644 "$service_file"

    # Reload systemd
    systemctl daemon-reload

    log_success "WiFi roaming service created at $service_file"
}

# Function to create systemd service for speedtest
create_speedtest_service() {
    local service_file="/etc/systemd/system/wifi-speedtest.service"
    local script_dir="/opt/wifi-roam"

    log_info "Creating systemd service for WiFi speedtest..."

    # Create the service file
    cat > "$service_file" << EOF
[Unit]
Description=WiFi Speedtest Service
After=network-online.target wifi-roaming.service
Wants=network-online.target
Requires=wifi-roaming.service

[Service]
Type=simple
ExecStart=$script_dir/speedtest_script.sh $SPEEDTEST_MIN_TIME $SPEEDTEST_MAX_TIME
Restart=always
RestartSec=30
RestartPreventExitStatus=2
User=root
WorkingDirectory=$script_dir
StandardOutput=journal
StandardError=journal
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

    # Set proper permissions
    chmod 644 "$service_file"

    # Reload systemd
    systemctl daemon-reload

    log_success "WiFi speedtest service created at $service_file"
}

# Function to create network interface configuration
create_interface_config() {
    log_info "Creating network interface configuration..."

    # Create interfaces configuration if using dhcpcd
    local dhcpcd_conf="/etc/dhcpcd.conf"

    # Backup existing dhcpcd.conf if it exists
    if [ -f "$dhcpcd_conf" ]; then
        cp "$dhcpcd_conf" "$dhcpcd_conf.backup.$(date +%s)"
        log_info "Backup created: $dhcpcd_conf.backup.$(date +%s)"
    fi

    # Configure dhcpcd for wireless interface
    cat > "$dhcpcd_conf" << EOF
# dhcpcd configuration for WiFi roaming
# See dhcpcd.conf(5) for details.

# Basic configuration
hostname

# Use the hardware address of the interface for the Client ID.
clientid

# Persist interface configuration when dhcpcd exits.
persistent

# Rapid commit support.
option rapid_commit

# A list of options to request from the DHCP server.
option domain_name_servers, domain_name, domain_search, host_name
option classless_static_routes
option interface_mtu

# Respect the network MTU. This is applied to DHCP routes.
option interface_mtu

# A ServerID is required by RFC2131.
require dhcp_server_identifier

# Generate SLAAC address using the hardware address of the interface
slaac hwaddr

# Configure all wireless interfaces to use DHCP
interface wlan*
    # Enable DHCP
    dhcp
    # Wait for link to be established
    waitip
    # Don't release DHCP lease on exit
    noipv4ll

# Also configure other common wireless interface names
interface wlx*
    dhcp
    waitip
    noipv4ll

interface wl*
    dhcp
    waitip
    noipv4ll
EOF

    log_success "dhcpcd configuration created"
}

# Function to auto-detect wireless interface
auto_detect_interface() {
    local detected_interface=""

    # Method 1: Use iw to list all wireless interfaces
    local iw_interfaces
    iw_interfaces=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' || true)

    if [ -n "$iw_interfaces" ]; then
        # Pick the first available interface
        local first_iface
        first_iface=$(echo "$iw_interfaces" | head -n1)
        if [ -n "$first_iface" ]; then
            detected_interface="$first_iface"
            echo "$detected_interface"
            return 0
        fi
    fi

    # Method 2: Look in /sys/class/net for wireless interfaces
    for iface in /sys/class/net/*/; do
        iface=$(basename "$iface")
        if [ -d "/sys/class/net/$iface/wireless" ] || [ -L "/sys/class/net/$iface/phy80211" ]; then
            detected_interface="$iface"
            echo "$detected_interface"
            return 0
        fi
    done

    # Method 3: Check common wireless interface names
    for iface in wlan0 wlan1 wlx* wl*; do
        if ip link show "$iface" >/dev/null 2>&1; then
            detected_interface="$iface"
            echo "$detected_interface"
            return 0
        fi
    done

    return 1
}

# Wait for wireless interface to be available
wait_for_interface() {
    local max_wait=60
    local wait_time=0
    local temp_file="/tmp/wifi_interface_detected"

    log_info "Waiting for wireless interface to become available..."

    while [ $wait_time -lt $max_wait ]; do
        local detected_iface
        if detected_iface=$(auto_detect_interface 2>/dev/null); then
            log_success "Wireless interface detected: $detected_iface"
            # Read from temp file instead of using stdout
            if [ -f "$temp_file" ]; then
                local interface_name
                interface_name=$(cat "$temp_file" | tr -d '\n\r')
                rm -f "$temp_file"
                echo "$interface_name"
                return 0
            fi
        fi

        sleep 2
        wait_time=$((wait_time + 2))

        if [ $((wait_time % 10)) -eq 0 ]; then
            log_info "Still waiting for wireless interface... (${wait_time}s elapsed)"
        fi
    done

    log_error "No wireless interface found after ${max_wait} seconds"
    return 1
}

# Function to create startup script
create_startup_script() {
    local startup_script="/usr/local/bin/wifi-startup.sh"
    local detected_interface=""

    log_info "Creating WiFi startup script..."

    # Auto-detect interface if not specified
    if [ -z "$INTERFACE" ]; then
        log_info "Auto-detecting wireless interface..."
        
        # Debug: Check what interfaces are available
        log_info "Available network interfaces:"
        ip link show | grep -E "^[0-9]+:" | awk '{print "  " $2}' | sed 's/:$//' || true
        
        log_info "Wireless interfaces (iw dev):"
        iw dev 2>/dev/null | grep Interface | awk '{print "  " $2}' || log_warning "iw dev failed or no wireless interfaces found"
        
        if detected_interface=$(auto_detect_interface); then
            if [ -n "$detected_interface" ]; then
                log_success "Auto-detected wireless interface: $detected_interface"
                INTERFACE="$detected_interface"
            else
                log_warning "Auto-detection returned empty string, using fallback"
                INTERFACE="wlan0"  # Default fallback
            fi
        else
            log_warning "Could not auto-detect interface. Using fallback methods..."
            
            # Fallback 1: Check for specific known interface
            if ip link show wlx5c628bed927b >/dev/null 2>&1; then
                log_success "Found known interface: wlx5c628bed927b"
                INTERFACE="wlx5c628bed927b"
            # Fallback 2: Check for any wlx* interface
            elif ls /sys/class/net/wlx* >/dev/null 2>&1; then
                local wlx_interface
                wlx_interface=$(ls /sys/class/net/wlx* | head -n1 | basename)
                log_success "Found wlx interface: $wlx_interface"
                INTERFACE="$wlx_interface"
            # Fallback 3: Use wlan0
            else
                log_warning "Using default fallback: wlan0"
                INTERFACE="wlan0"
            fi
        fi
    fi

    cat > "$startup_script" << EOF
#!/bin/bash

# WiFi Startup Script
# This script starts wpa_supplicant and dhcpcd for the wireless interface

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "\${BLUE}[INFO]\${NC} \$1"
}

log_success() {
    echo -e "\${GREEN}[SUCCESS]\${NC} \$1"
}

log_warning() {
    echo -e "\${YELLOW}[WARNING]\${NC} \$1"
}

log_error() {
    echo -e "\${RED}[ERROR]\${NC} \$1"
}

# Function to auto-detect wireless interface
auto_detect_interface() {
    local detected_interface=""

    # Method 1: Use iw to list all wireless interfaces
    local iw_interfaces
    iw_interfaces=\$(iw dev 2>/dev/null | grep Interface | awk '{print \$2}' || true)

    if [ -n "\$iw_interfaces" ]; then
        local first_iface
        first_iface=\$(echo "\$iw_interfaces" | head -n1)
        if [ -n "\$first_iface" ]; then
            detected_interface="\$first_iface"
            log_info "Auto-detection method 1 found: \$detected_interface"
            # Use echo but redirect stderr to avoid log mixing
            echo "\$detected_interface" 1>&1 2>/dev/null
            log_info "Auto-detection method 1 output completed"
            return 0
        fi
    fi

    # Method 2: Look in /sys/class/net for wireless interfaces
    for iface in /sys/class/net/*/; do
        iface=\$(basename "\$iface")
        if [ -d "/sys/class/net/\$iface/wireless" ] || [ -L "/sys/class/net/\$iface/phy80211" ]; then
            detected_interface="\$iface"
            log_info "Auto-detection method 2 found: \$detected_interface"
            # Use echo but redirect stderr to avoid log mixing
            echo "\$detected_interface" 1>&1 2>/dev/null
            log_info "Auto-detection method 2 output completed"
            return 0
        fi
    done

    # Method 3: Check common wireless interface names
    for iface in wlan0 wlan1 wlx* wl*; do
        if ip link show "\$iface" >/dev/null 2>&1; then
            detected_interface="\$iface"
            log_info "Auto-detection method 3 found: \$detected_interface"
            # Use echo but redirect stderr to avoid log mixing
            echo "\$detected_interface" 1>&1 2>/dev/null
            log_info "Auto-detection method 3 output completed"
            return 0
        fi
    done

    return 1
}

# Wait for wireless interface to be available
wait_for_interface() {
    local max_wait=60
    local wait_time=0

    log_info "Waiting for wireless interface to become available..."

    while [ \$wait_time -lt \$max_wait ]; do
        local detected_iface
        if detected_iface=\$(auto_detect_interface 2>/dev/null); then
            log_success "Wireless interface detected: \$detected_iface"
            # Debug: Show what we're about to output
            log_info "About to output interface name: '\$detected_iface'"
            # Output the interface name to stdout (separate from log messages)
            echo "\$detected_iface" 1>&1 2>/dev/null
            # Debug: Verify output
            log_info "Interface name output completed"
            return 0
        fi

        sleep 2
        wait_time=\$((wait_time + 2))

        if [ \$((wait_time % 10)) -eq 0 ]; then
            log_info "Still waiting for wireless interface... (\${wait_time}s elapsed)"
        fi
    done

    log_error "No wireless interface found after \${max_wait} seconds"
    return 1
}

# Main startup sequence
main() {
    log_info "Starting WiFi configuration..."

    # Use the detected interface directly
    local wifi_interface="$INTERFACE"
    log_info "Using wireless interface: \$wifi_interface"
    
    # Validate the interface name
    if [ -z "\$wifi_interface" ]; then
        log_error "Interface name is empty"
        exit 1
    fi
    
    if [[ ! "\$wifi_interface" =~ ^[a-zA-Z0-9_]+$ ]]; then
        log_error "Invalid interface name: '\$wifi_interface'"
        exit 1
    fi

    # Wait for interface to be available before proceeding
    log_info "Waiting for interface \$wifi_interface to be available..."
    local wait_count=0
    local max_wait=60
    
    while [ \$wait_count -lt \$max_wait ]; do
        if ip link show "\$wifi_interface" >/dev/null 2>&1; then
            log_success "Interface \$wifi_interface is now available"
            break
        fi
        sleep 2
        wait_count=\$((wait_count + 2))
        if [ \$((wait_count % 10)) -eq 0 ]; then
            log_info "Still waiting for interface \$wifi_interface... (\$wait_count seconds elapsed)"
        fi
    done

    if [ \$wait_count -ge \$max_wait ]; then
        log_error "Interface \$wifi_interface never became available after \$max_wait seconds"
        log_error "Available network interfaces:"
        ip link show | grep -E "^[0-9]+:" | awk '{print "  " \$2}' | sed 's/:$//' || true
        exit 1
    fi

    # Bring interface up
    log_info "Bringing interface \$wifi_interface up..."
    if ! ip link set "\$wifi_interface" up; then
        log_error "Failed to bring interface up"
        exit 1
    fi

    # Kill any existing wpa_supplicant processes for this interface
    if pgrep -f "wpa_supplicant.*\$wifi_interface" > /dev/null; then
        log_info "Stopping existing wpa_supplicant for \$wifi_interface..."
        pkill -f "wpa_supplicant.*\$wifi_interface" || true
        sleep 2
    fi

    # Start wpa_supplicant
    log_info "Starting wpa_supplicant for \$wifi_interface..."
    if ! wpa_supplicant -B -i "\$wifi_interface" -c /etc/wpa_supplicant/wpa_supplicant.conf -D nl80211; then
        log_error "Failed to start wpa_supplicant"
        exit 1
    fi

    # Wait a moment for wpa_supplicant to initialize
    sleep 5

    # Wait for authentication to complete
    log_info "Waiting for authentication..."
    local auth_wait=0
    local max_auth_wait=30

    while [ \$auth_wait -lt \$max_auth_wait ]; do
        if wpa_cli -i "\$wifi_interface" status | grep -q "wpa_state=COMPLETED"; then
            log_success "Authentication completed"
            break
        fi
        sleep 2
        auth_wait=\$((auth_wait + 2))
    done

    if [ \$auth_wait -ge \$max_auth_wait ]; then
        log_warning "Authentication may not have completed, continuing with DHCP..."
    fi

    # Start DHCP client
    log_info "Starting DHCP client for \$wifi_interface..."
    
    # Kill any existing dhcpcd processes for this interface
    if pgrep -f "dhcpcd.*\$wifi_interface" > /dev/null; then
        log_info "Stopping existing dhcpcd for \$wifi_interface..."
        pkill -f "dhcpcd.*\$wifi_interface" || true
        sleep 2
    fi
    
    # Start dhcpcd and wait for it to complete
    log_info "Starting dhcpcd for \$wifi_interface..."
    if dhcpcd -w "\$wifi_interface"; then
        log_success "DHCP client started successfully"
        
        # Wait for IP assignment
        log_info "Waiting for IP address assignment..."
        local dhcp_wait=0
        local max_dhcp_wait=60
        
        while [ \$dhcp_wait -lt \$max_dhcp_wait ]; do
            if ip addr show "\$wifi_interface" | grep -q "inet "; then
                local ip_addr
                ip_addr=\$(ip addr show "\$wifi_interface" | grep "inet " | awk '{print \$2}' | head -n1)
                log_success "Network connection established. IP address: \$ip_addr"
                break
            fi
            
            sleep 2
            dhcp_wait=\$((dhcp_wait + 2))
            
            if [ \$((dhcp_wait % 10)) -eq 0 ]; then
                log_info "Still waiting for DHCP... (\${dhcp_wait}s elapsed)"
            fi
        done
        
        if [ \$dhcp_wait -ge \$max_dhcp_wait ]; then
            log_warning "DHCP timeout - no IP address assigned after \${max_dhcp_wait} seconds"
            log_info "Checking dhcpcd status..."
            if pgrep -f "dhcpcd.*\$wifi_interface" > /dev/null; then
                log_info "dhcpcd is still running, checking logs..."
                journalctl -u dhcpcd --since "1 minute ago" | tail -20 || true
            fi
        fi
    else
        log_error "Failed to start DHCP client"
        log_info "Attempting to start dhcpcd manually..."
        if dhcpcd "\$wifi_interface"; then
            log_success "DHCP client started manually"
        else
            log_error "DHCP client failed to start even manually"
        fi
    fi

    # Final status check
    log_info "=== Final Network Status ==="
    
    # Check interface status
    if ip link show "\$wifi_interface" | grep -q "UP"; then
        log_success "Interface \$wifi_interface is UP"
    else
        log_warning "Interface \$wifi_interface is DOWN"
    fi
    
    # Check IP address
    if ip addr show "\$wifi_interface" | grep -q "inet "; then
        local ip_addr
        ip_addr=\$(ip addr show "\$wifi_interface" | grep "inet " | awk '{print \$2}' | head -n1)
        log_success "IP Address: \$ip_addr"
    else
        log_error "No IP address assigned"
    fi
    
    # Check routing
    if ip route show | grep -q "\$wifi_interface"; then
        log_success "Routing table contains \$wifi_interface"
        ip route show | grep "\$wifi_interface" | head -3
    else
        log_warning "No routes found for \$wifi_interface"
    fi
    
    # Check dhcpcd status
    if pgrep -f "dhcpcd.*\$wifi_interface" > /dev/null; then
        log_success "dhcpcd is running for \$wifi_interface"
    else
        log_warning "dhcpcd is not running for \$wifi_interface"
    fi
    
    log_info "==========================="
    log_success "WiFi startup completed for interface \$wifi_interface"
}

# Run main function
main "$@"
EOF

    chmod +x "$startup_script"
    log_success "WiFi startup script created at $startup_script"
}

# Function to create systemd service for WiFi startup
create_wifi_startup_service() {
    local service_file="/etc/systemd/system/wifi-startup.service"

    log_info "Creating WiFi startup service..."

    cat > "$service_file" << EOF
[Unit]
Description=WiFi Startup Service
After=network-pre.target
Before=network.target
Wants=network-pre.target
Requires=dhcpcd.service
After=dhcpcd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wifi-startup.sh
RemainAfterExit=yes
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$service_file"
    systemctl daemon-reload

    log_success "WiFi startup service created"
}

# Function to update roaming script with parameters
update_roaming_script() {
    local roam_script="./roam_script.sh"

    log_info "Updating roaming script with parameters..."

    if [ ! -f "$roam_script" ]; then
        log_error "Roaming script '$roam_script' not found in current directory"
        exit 1
    fi

    # Update default values in the roaming script
    sed -i "s/DEFAULT_SSID=\".*\"/DEFAULT_SSID=\"$SSID\"/" "$roam_script"
    sed -i "s/DEFAULT_MIN_TIME=.*/DEFAULT_MIN_TIME=$MIN_TIME/" "$roam_script"
    sed -i "s/DEFAULT_MAX_TIME=.*/DEFAULT_MAX_TIME=$MAX_TIME/" "$roam_script"
    sed -i "s/DEFAULT_MIN_SIGNAL=.*/DEFAULT_MIN_SIGNAL=$MIN_SIGNAL/" "$roam_script"

    # Make sure it's executable
    chmod +x "$roam_script"

    log_success "Roaming script updated with parameters"
}

# Function to enable and start services
enable_services() {
    log_info "Enabling and starting services..."

    # Enable and start WiFi startup service
    systemctl enable wifi-startup.service
    log_success "WiFi startup service enabled"

    # Start the WiFi startup service now
    log_info "Starting WiFi connection..."
    if systemctl start wifi-startup.service; then
        log_success "WiFi startup service started"
    else
        log_warning "WiFi startup service failed to start, check logs with: journalctl -u wifi-startup.service"
    fi

    # Wait longer for WiFi to connect and stabilize
    log_info "Waiting for WiFi connection to stabilize..."
    sleep 30

    # Enable roaming service but don't start it immediately
    systemctl enable wifi-roaming.service
    log_success "WiFi roaming service enabled"

    # Start roaming service with a longer delay
    log_info "Starting WiFi roaming service (with delay for stability)..."
    sleep 10
    if systemctl start wifi-roaming.service; then
        log_success "WiFi roaming service started"
        # Give it a moment to initialize
        sleep 5
        # Check if it's actually running
        if systemctl is-active wifi-roaming.service >/dev/null 2>&1; then
            log_success "WiFi roaming service is active and running"
        else
            log_warning "WiFi roaming service started but may not be running properly"
            log_info "Check logs with: journalctl -u wifi-roaming.service -f"
        fi
    else
        log_warning "WiFi roaming service failed to start, check logs with: journalctl -u wifi-roaming.service"
    fi

    # Enable and start speedtest service
    systemctl enable wifi-speedtest.service
    log_success "WiFi speedtest service enabled"

    log_info "Starting WiFi speedtest service..."
    if systemctl start wifi-speedtest.service; then
        log_success "WiFi speedtest service started"
    else
        log_warning "WiFi speedtest service failed to start, check logs with: journalctl -u wifi-speedtest.service"
    fi
}

# Function to show service status
show_status() {
    log_info "=== Service Status ==="

    echo ""
    log_info "WiFi Startup Service:"
    systemctl status wifi-startup.service --no-pager -l || true

    echo ""
    log_info "WiFi Roaming Service:"
    systemctl status wifi-roaming.service --no-pager -l || true

    echo ""
    log_info "WiFi Speedtest Service:"
    systemctl status wifi-speedtest.service --no-pager -l || true

    echo ""
    log_info "Network Interfaces:"
    ip addr show | grep -E "^[0-9]+:|inet " || true

    echo ""
    log_info "===================="
}

# Function to check and restart DHCP if needed
check_and_restart_dhcp() {
    local interface="$1"
    
    log_info "Checking DHCP status for interface $interface..."
    
    # Check if interface has IP
    if ip addr show "$interface" | grep -q "inet "; then
        local ip_addr
        ip_addr=$(ip addr show "$interface" | grep "inet " | awk '{print $2}' | head -n1)
        log_success "Interface $interface already has IP: $ip_addr"
        return 0
    fi
    
    log_warning "Interface $interface has no IP address, attempting to restart DHCP..."
    
    # Kill existing dhcpcd for this interface
    if pgrep -f "dhcpcd.*$interface" > /dev/null; then
        log_info "Stopping existing dhcpcd for $interface..."
        pkill -f "dhcpcd.*$interface" || true
        sleep 3
    fi
    
    # Start dhcpcd
    log_info "Starting dhcpcd for $interface..."
    if dhcpcd "$interface"; then
        log_success "dhcpcd started successfully"
        
        # Wait for IP assignment
        local wait_time=0
        local max_wait=30
        
        while [ $wait_time -lt $max_wait ]; do
            if ip addr show "$interface" | grep -q "inet "; then
                local ip_addr
                ip_addr=$(ip addr show "$interface" | grep "inet " | awk '{print $2}' | head -n1)
                log_success "IP address assigned: $ip_addr"
                return 0
            fi
            
            sleep 2
            wait_time=$((wait_time + 2))
        done
        
        log_error "DHCP timeout after $max_wait seconds"
        return 1
    else
        log_error "Failed to start dhcpcd"
        return 1
    fi
}

# Main function
main() {
    local params_file="${1:-./parameters.txt}"

    log_info "WiFi Setup Script for EAP-PEAP MSCHAPv2 with Roaming"
    log_info "=================================================="

    # Check if running as root
    check_root

    # Load parameters
    load_parameters "$params_file"

    # Install required packages
    install_packages

    # Disable conflicting services
    disable_conflicting_services

    # Configure wpa_supplicant
    configure_wpa_supplicant

    # Update roaming script with parameters
    update_roaming_script

    # Create startup script and service
    create_startup_script
    create_wifi_startup_service

    # Create roaming service
    create_roaming_service

    # Create speedtest service
    create_speedtest_service

    # Enable and start services
    enable_services

    # Show final status
    echo ""
    log_success "Setup completed successfully!"
    echo ""
    log_info "Services created:"
    log_info "  - wifi-startup.service: Handles initial WiFi connection"
    log_info "  - wifi-roaming.service: Handles automatic roaming"
    log_info "  - wifi-speedtest.service: Handles periodic speedtests"
    echo ""
    log_info "To check service status:"
    log_info "  systemctl status wifi-startup.service"
    log_info "  systemctl status wifi-roaming.service"
    log_info "  systemctl status wifi-speedtest.service"
    echo ""
    log_info "To view logs:"
    log_info "  journalctl -u wifi-startup.service -f"
    log_info "  journalctl -u wifi-roaming.service -f"
    log_info "  journalctl -u wifi-speedtest.service -f"
    echo ""

    # Show current status
    show_status
}

# Handle help
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "WiFi Setup Script for EAP-PEAP MSCHAPv2 with Roaming"
    echo ""
    echo "Usage: $0 [parameters_file]"
    echo ""
    echo "Default parameters file: ./parameters.txt"
    echo ""
    echo "This script will:"
    echo "  1. Install required packages (wpasupplicant, dhcpcd5, etc.)"
    echo "  2. Disable conflicting network services"
    echo "  3. Configure wpa_supplicant.conf with your credentials"
    echo "  4. Create systemd services for WiFi startup and roaming"
    echo "  5. Enable services to start automatically on boot"
    echo ""
    echo "Required files in current directory:"
    echo "  - parameters.txt (configuration parameters)"
    echo "  - wpa_supplicant.conf (template configuration)"
    echo "  - roam_script.sh (roaming script)"
    exit 0
fi

# Run main function
main "$@"