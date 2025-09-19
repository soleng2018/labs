#!/bin/bash

# WiFi Roaming Script
# This script automatically roams between WiFi access points based on signal strength

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARAMETERS_FILE="$SCRIPT_DIR/parameters.txt"
LOG_FILE="/var/log/roam_debug.log"
CURRENT_BSSID=""
FIRST_CONNECTION=true
ROAM_ITERATION=0

# Logging function
log() {
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    local message="$timestamp $1"
    echo "$message" >&2
    echo "$message" | sudo tee -a "$LOG_FILE" > /dev/null 2>&1
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check and install required tools
check_required_tools() {
    log "Checking required tools..."
    
    local required_tools=("iw" "iwconfig" "wpa_cli" "dhcpcd" "ip" "grep" "awk" "cut" "tr" "sed")
    local missing_tools=()
    local install_command=""
    
    # Detect package manager and set install command
    if command -v apt-get >/dev/null 2>&1; then
        install_command="apt-get install -y"
        log "Detected apt package manager"
    elif command -v yum >/dev/null 2>&1; then
        install_command="yum install -y"
        log "Detected yum package manager"
    elif command -v dnf >/dev/null 2>&1; then
        install_command="dnf install -y"
        log "Detected dnf package manager"
    elif command -v pacman >/dev/null 2>&1; then
        install_command="pacman -S --noconfirm"
        log "Detected pacman package manager"
    elif command -v zypper >/dev/null 2>&1; then
        install_command="zypper install -y"
        log "Detected zypper package manager"
    else
        error_exit "No supported package manager found (apt, yum, dnf, pacman, zypper)"
    fi
    
    # Check each required tool
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log "  ✓ $tool: Found"
        else
            log "  ✗ $tool: Missing"
            missing_tools+=("$tool")
        fi
    done
    
    # If tools are missing, try to install them
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log "Missing tools: ${missing_tools[*]}"
        log "Attempting to install missing tools..."
        
        # Map tool names to package names
        local package_map=()
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "iw")
                    package_map+=("wireless-tools")
                    ;;
                "iwconfig")
                    package_map+=("wireless-tools")
                    ;;
                "wpa_cli")
                    package_map+=("wpa_supplicant")
                    ;;
                "dhcpcd")
                    package_map+=("dhcpcd5")
                    ;;
                "ip"|"grep"|"awk"|"cut"|"tr"|"sed")
                    package_map+=("coreutils")
                    ;;
                *)
                    package_map+=("$tool")
                    ;;
            esac
        done
        
        # Remove duplicates
        local unique_packages=($(printf "%s\n" "${package_map[@]}" | sort -u))
        log "Installing packages: ${unique_packages[*]}"
        
        if sudo $install_command "${unique_packages[@]}" >/dev/null 2>&1; then
            log "Package installation completed"
            
            # Verify tools are now available
            local still_missing=()
            for tool in "${missing_tools[@]}"; do
                if command -v "$tool" >/dev/null 2>&1; then
                    log "  ✓ $tool: Now available"
                else
                    still_missing+=("$tool")
                fi
            done
            
            if [[ ${#still_missing[@]} -gt 0 ]]; then
                error_exit "Failed to install required tools: ${still_missing[*]}"
            fi
        else
            error_exit "Failed to install required packages. Please install manually: ${unique_packages[*]}"
        fi
    else
        log "All required tools are available"
    fi
}

# Load parameters from file
load_parameters() {
    if [[ ! -f "$PARAMETERS_FILE" ]]; then
        error_exit "Parameters file not found: $PARAMETERS_FILE"
    fi
    
    log "Loading parameters from $PARAMETERS_FILE"
    
    # Source the parameters file
    source "$PARAMETERS_FILE"
    
    # Validate parameters
    if [[ -z "$SSID_Name" ]]; then
        error_exit "SSID_Name not defined in parameters.txt"
    fi
    
    if ! [[ "$Min_Time_Roam" =~ ^[0-9]+$ ]]; then
        error_exit "Min_Time_Roam must be an integer"
    fi
    
    if ! [[ "$Max_Time_Roam" =~ ^[0-9]+$ ]]; then
        error_exit "Max_Time_Roam must be an integer"
    fi
    
    if [[ $Min_Time_Roam -gt $Max_Time_Roam ]]; then
        error_exit "Min_Time_Roam cannot be greater than Max_Time_Roam"
    fi
    
    if ! [[ "$Min_Signal" =~ ^-?[0-9]+$ ]]; then
        error_exit "Min_Signal must be an integer"
    fi
    
    if [[ "$Preferred_Band" != "2.4G" && "$Preferred_Band" != "5G" && "$Preferred_Band" != "6G" ]]; then
        error_exit "Preferred_Band must be 2.4G, 5G, or 6G"
    fi
    
    log "Parameters loaded successfully:"
    log "  SSID: $SSID_Name"
    log "  Roam time: $Min_Time_Roam-$Max_Time_Roam minutes"
    log "  Min signal: $Min_Signal dBm"
    log "  Preferred band: $Preferred_Band"
}

# Detect wireless interface
detect_wireless_interface() {
    log "Detecting wireless interfaces..."
    
    # Get all network interfaces
    interfaces=$(ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print $2}' | grep -v lo)
    log "Found network interfaces: $interfaces"
    
    wireless_interfaces=()
    for iface in $interfaces; do
        log "Checking interface: $iface"
        
        # Check multiple methods to detect wireless interfaces
        local is_wireless=false
        
        # Method 1: Check if iw dev works
        if iw dev "$iface" info >/dev/null 2>&1; then
            log "  -> iw dev $iface info: SUCCESS"
            is_wireless=true
        else
            log "  -> iw dev $iface info: FAILED"
        fi
        
        # Method 2: Check if iwconfig shows wireless info
        if iwconfig "$iface" 2>/dev/null | grep -q "IEEE 802.11"; then
            log "  -> iwconfig $iface: IEEE 802.11 detected"
            is_wireless=true
        else
            log "  -> iwconfig $iface: No IEEE 802.11"
        fi
        
        # Method 3: Check if interface name suggests wireless (wlx, wlan, etc.)
        if [[ "$iface" =~ ^(wlx|wlan|wlp|wifi) ]]; then
            log "  -> Interface name suggests wireless: $iface"
            is_wireless=true
        fi
        
        if [[ "$is_wireless" == "true" ]]; then
            wireless_interfaces+=("$iface")
            log "  -> Added $iface to wireless interfaces list"
        fi
    done
    
    log "Wireless interfaces found: ${wireless_interfaces[*]}"
    
    if [[ ${#wireless_interfaces[@]} -eq 0 ]]; then
        error_exit "No wireless interfaces found. Available interfaces: $interfaces"
    fi
    
    # Select the first wireless interface
    INTERFACE="${wireless_interfaces[0]}"
    log "Selected wireless interface: $INTERFACE"
    
    if [[ ${#wireless_interfaces[@]} -gt 1 ]]; then
        log "Multiple wireless interfaces found: ${wireless_interfaces[*]}"
        log "Using: $INTERFACE"
    fi
    
    # Verify the selected interface is actually working
    log "Verifying selected interface $INTERFACE..."
    if iw dev "$INTERFACE" info >/dev/null 2>&1; then
        log "Interface verification successful"
    else
        log "Warning: Interface verification failed, but proceeding anyway"
    fi
}

# Scan for SSID on all bands
scan_for_ssid() {
    log "Scanning for SSID: $SSID_Name"
    
    # Clear any existing scan results first
    log "Clearing previous scan results..."
    sudo wpa_cli -i "$INTERFACE" scan_results >/dev/null 2>&1
    
    # Perform multiple scan attempts for better coverage
    local scan_attempts=3
    local scan_success=false
    
    for attempt in $(seq 1 $scan_attempts); do
        log "Scan attempt $attempt of $scan_attempts..."
        
        # Trigger scan
        if sudo wpa_cli -i "$INTERFACE" scan >/dev/null 2>&1; then
            # Wait for scan to complete (longer wait for comprehensive scan)
            sleep 8
            
            # Get scan results
            local current_scan_results=$(sudo wpa_cli -i "$INTERFACE" scan_results 2>/dev/null)
            
            if [[ -n "$current_scan_results" ]]; then
                # Count target SSID BSSIDs in this scan
                local target_count=0
                while IFS=$'\t' read -r bssid frequency signal_level flags ssid; do
                    if [[ "$bssid" != "bssid" ]]; then
                        local clean_ssid=$(echo "$ssid" | sed 's/^"//;s/"$//')
                        if [[ "$clean_ssid" == "$SSID_Name" ]]; then
                            target_count=$((target_count + 1))
                        fi
                    fi
                done <<< "$current_scan_results"
                
                scan_results="$current_scan_results"
                scan_success=true
                log "Scan attempt $attempt successful - found $target_count BSSIDs for target SSID"
                break
            else
                log "Scan attempt $attempt returned no results, retrying..."
            fi
        else
            log "Scan attempt $attempt failed, retrying..."
        fi
        
        # Wait before retry
        if [[ $attempt -lt $scan_attempts ]]; then
            sleep 3
        fi
    done
    
    if [[ "$scan_success" != "true" ]]; then
        error_exit "Failed to get scan results after $scan_attempts attempts"
    fi
    
    log "Scan completed, processing results..."
    log "Raw scan results (target SSID only):"
    echo "$scan_results" | while IFS= read -r line; do
        # Only show lines that contain the target SSID or are header lines
        if [[ "$line" =~ $target_ssid || "$line" =~ ^bssid ]]; then
            log "  $line"
        fi
    done
    
    # Filter and show only target SSID results
    log "Filtered scan results for SSID '$SSID_Name':"
    local target_ssid_count=0
    while IFS=$'\t' read -r bssid frequency signal_level flags ssid; do
        # Skip header line
        if [[ "$bssid" == "bssid" ]]; then
            continue
        fi
        
        # Check if SSID matches (handle quoted SSIDs)
        local clean_ssid=$(echo "$ssid" | sed 's/^"//;s/"$//')
        if [[ "$clean_ssid" == "$SSID_Name" ]]; then
            target_ssid_count=$((target_ssid_count + 1))
            local band=$(get_frequency_band $frequency)
            log "  BSSID: $bssid, Signal: $signal_level dBm, Frequency: $frequency MHz, Band: $band, SSID: '$clean_ssid'"
        fi
    done <<< "$scan_results"
    
    log "Found $target_ssid_count BSSIDs for target SSID '$SSID_Name'"
}

# Get BSSIDs for the target SSID
get_bssids() {
    local target_ssid="$1"
    local min_signal="$2"
    
    log "Looking for BSSIDs for SSID: $target_ssid with signal >= $min_signal dBm"
    
    # Parse scan results to find matching SSID
    local bssids=()
    local signals=()
    local frequencies=()
    local total_networks=0
    local matching_networks=0
    local filtered_networks=0
    
    while IFS=$'\t' read -r bssid frequency signal_level flags ssid; do
        # Skip header line
        if [[ "$bssid" == "bssid" ]]; then
            continue
        fi
        
        total_networks=$((total_networks + 1))
        
        # Check if SSID matches (handle quoted SSIDs)
        local clean_ssid=$(echo "$ssid" | sed 's/^"//;s/"$//')
        if [[ "$clean_ssid" == "$target_ssid" ]]; then
            matching_networks=$((matching_networks + 1))
            log "Processing target SSID network: BSSID=$bssid, SSID='$ssid', Signal=$signal_level dBm, Freq=$frequency MHz"
            log "  -> SSID matches target: '$clean_ssid'"
            
            # Convert signal level to integer for comparison (remove decimal part)
            local signal_int=$(echo "$signal_level" | cut -d. -f1)
            if [[ $signal_int -ge $min_signal ]]; then
                bssids+=("$bssid")
                signals+=("$signal_int")
                frequencies+=("$frequency")
                log "  -> BSSID ACCEPTED: $bssid, Signal: $signal_int dBm, Frequency: $frequency MHz"
            else
                filtered_networks=$((filtered_networks + 1))
                log "  -> BSSID FILTERED: $bssid (signal: $signal_int dBm < $min_signal dBm)"
            fi
        else
            # Only log non-target SSIDs if they're empty or have issues
            if [[ -z "$clean_ssid" || "$clean_ssid" == "" ]]; then
                log "Processing hidden/empty SSID: BSSID=$bssid, Signal=$signal_level dBm, Freq=$frequency MHz"
            fi
        fi
    done <<< "$scan_results"
    
    log "Scan analysis summary:"
    log "  Total networks found: $total_networks"
    log "  Networks matching SSID '$target_ssid': $matching_networks"
    log "  Networks filtered by signal strength: $filtered_networks"
    log "  Suitable BSSIDs: ${#bssids[@]}"
    
    if [[ ${#bssids[@]} -eq 0 ]]; then
        error_exit "No BSSIDs found for SSID '$target_ssid' meeting signal requirements"
    fi
    
    # Return BSSIDs as global arrays
    BSSIDS=("${bssids[@]}")
    SIGNALS=("${signals[@]}")
    FREQUENCIES=("${frequencies[@]}")
    
    log "Found ${#BSSIDS[@]} suitable BSSIDs for roaming"
}

# Get frequency band from frequency in MHz
get_frequency_band() {
    local freq="$1"
    # Convert to integer to handle decimal values like 5220.0
    local freq_int=$(echo "$freq" | cut -d. -f1)
    
    if [[ $freq_int -ge 2400 && $freq_int -le 2500 ]]; then
        echo "2.4G"
    elif [[ $freq_int -ge 5000 && $freq_int -le 6000 ]]; then
        echo "5G"
    elif [[ $freq_int -ge 6000 && $freq_int -le 7000 ]]; then
        echo "6G"
    else
        echo "Unknown"
    fi
}

# Check and renew IP address if needed
check_and_renew_ip() {
    local interface="$1"
    local force_renew="${2:-false}"
    
    # Check current IP address
    local ip_address=$(ip addr show "$interface" | grep -oP 'inet \K[0-9.]+' | head -1)
    
    if [[ -n "$ip_address" && "$force_renew" != "true" ]]; then
        log "IP address already assigned: $ip_address"
        return 0
    fi
    
    if [[ -z "$ip_address" || "$force_renew" == "true" ]]; then
        log "No IP address found or renewal requested, attempting to renew..."
        
        # Try to renew IP address
        if sudo dhcpcd "$interface" >/dev/null 2>&1; then
            log "Running dhcpcd for IP renewal..."
            sleep 3  # Wait for IP assignment
            
            # Check again for IP address
            ip_address=$(ip addr show "$interface" | grep -oP 'inet \K[0-9.]+' | head -1)
            if [[ -n "$ip_address" ]]; then
                log "IP address renewed successfully: $ip_address"
                
                # Show network details
                local gateway=$(ip route | grep default | grep "$interface" | awk '{print $3}' | head -1)
                local dns_servers=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
                log "  Gateway: ${gateway:-'Not found'}"
                log "  DNS servers: ${dns_servers:-'Not found'}"
                return 0
            else
                log "Warning: IP address renewal failed"
                return 1
            fi
        else
            log "Warning: Failed to run dhcpcd for IP renewal"
            return 1
        fi
    fi
}

# Select best BSSID based on preferred band and signal strength
select_best_bssid() {
    local best_index=0
    local best_signal=${SIGNALS[0]}
    local best_band=$(get_frequency_band ${FREQUENCIES[0]})
    
    log "Selecting best BSSID from ${#BSSIDS[@]} candidates (Preferred band: $Preferred_Band):"
    
    # First, try to find BSSIDs on the preferred band
    local preferred_candidates=()
    local preferred_signals=()
    local preferred_indices=()
    
    for i in "${!FREQUENCIES[@]}"; do
        local band=$(get_frequency_band ${FREQUENCIES[$i]})
        log "  BSSID: ${BSSIDS[$i]}, Signal: ${SIGNALS[$i]} dBm, Frequency: ${FREQUENCIES[$i]} MHz, Band: $band"
        
        if [[ "$band" == "$Preferred_Band" ]]; then
            preferred_candidates+=("${BSSIDS[$i]}")
            preferred_signals+=("${SIGNALS[$i]}")
            preferred_indices+=("$i")
            log "    -> Preferred band candidate"
        fi
    done
    
    # If we have preferred band candidates, select the best one
    if [[ ${#preferred_candidates[@]} -gt 0 ]]; then
        log "Found ${#preferred_candidates[@]} candidates on preferred band ($Preferred_Band):"
        best_index=${preferred_indices[0]}
        best_signal=${preferred_signals[0]}
        
        for i in "${!preferred_signals[@]}"; do
            log "  Preferred band BSSID: ${preferred_candidates[$i]}, Signal: ${preferred_signals[$i]} dBm"
            if [[ ${preferred_signals[$i]} -gt $best_signal ]]; then
                best_signal=${preferred_signals[$i]}
                best_index=${preferred_indices[$i]}
                log "    -> New best preferred band candidate"
            fi
        done
        
        local selected_band=$(get_frequency_band ${FREQUENCIES[$best_index]})
        log "Selected best BSSID from preferred band: ${BSSIDS[$best_index]} with signal ${SIGNALS[$best_index]} dBm on $selected_band"
    else
        # No preferred band candidates, select best overall signal
        log "No candidates found on preferred band ($Preferred_Band), selecting best signal overall:"
        for i in "${!SIGNALS[@]}"; do
            local band=$(get_frequency_band ${FREQUENCIES[$i]})
            if [[ ${SIGNALS[$i]} -gt $best_signal ]]; then
                best_signal=${SIGNALS[$i]}
                best_index=$i
                best_band=$band
                log "    -> New best overall candidate (Band: $band)"
            fi
        done
        
        log "Selected best BSSID overall: ${BSSIDS[$best_index]} with signal ${SIGNALS[$best_index]} dBm on $best_band"
    fi
    
    # Return only the BSSID without any logging
    echo "${BSSIDS[$best_index]}"
}

# Select a different BSSID to roam to (not the current one)
select_different_bssid() {
    # Get current BSSID from wpa_cli status to ensure accuracy
    local current_bssid=$(sudo wpa_cli -i "$INTERFACE" status | grep bssid | cut -d= -f2 | tr -d ' ')
    if [[ -z "$current_bssid" || "$current_bssid" == "00:00:00:00:00:00" ]]; then
        current_bssid="$CURRENT_BSSID"
    fi
    
    log "Selecting different BSSID for roaming (current: $current_bssid):"
    log "All available BSSIDs: ${BSSIDS[*]}"
    
    # Find all BSSIDs that are different from current and meet signal requirements
    local available_bssids=()
    local available_signals=()
    local available_frequencies=()
    local available_indices=()
    
    for i in "${!BSSIDS[@]}"; do
        log "  Checking BSSID: ${BSSIDS[$i]} (current: $current_bssid)"
        # Skip if this is the current BSSID
        if [[ "${BSSIDS[$i]}" != "$current_bssid" ]]; then
            available_bssids+=("${BSSIDS[$i]}")
            available_signals+=("${SIGNALS[$i]}")
            available_frequencies+=("${FREQUENCIES[$i]}")
            available_indices+=("$i")
            local band=$(get_frequency_band ${FREQUENCIES[$i]})
            log "    -> Available BSSID: ${BSSIDS[$i]}, Signal: ${SIGNALS[$i]} dBm, Frequency: ${FREQUENCIES[$i]} MHz, Band: $band"
        else
            log "    -> Skipping current BSSID: ${BSSIDS[$i]}"
        fi
    done
    
    if [[ ${#available_bssids[@]} -eq 0 ]]; then
        log "No different BSSIDs available for roaming"
        echo ""
        return
    fi
    
    # Prefer BSSIDs on the preferred band
    local preferred_candidates=()
    local preferred_signals=()
    local preferred_frequencies=()
    local preferred_indices=()
    
    for i in "${!available_frequencies[@]}"; do
        local band=$(get_frequency_band ${available_frequencies[$i]})
        if [[ "$band" == "$Preferred_Band" ]]; then
            preferred_candidates+=("${available_bssids[$i]}")
            preferred_signals+=("${available_signals[$i]}")
            preferred_frequencies+=("${available_frequencies[$i]}")
            preferred_indices+=("${available_indices[$i]}")
            log "    -> Preferred band candidate: ${available_bssids[$i]}"
        fi
    done
    
    # Select from preferred band if available, otherwise select best signal
    local selected_bssid=""
    if [[ ${#preferred_candidates[@]} -gt 0 ]]; then
        log "Found ${#preferred_candidates[@]} candidates on preferred band ($Preferred_Band)"
        # Select the best signal from preferred band
        local best_signal=${preferred_signals[0]}
        local best_candidate_index=0
        for i in "${!preferred_signals[@]}"; do
            if [[ ${preferred_signals[$i]} -gt $best_signal ]]; then
                best_signal=${preferred_signals[$i]}
                best_candidate_index=$i
            fi
        done
        selected_bssid="${preferred_candidates[$best_candidate_index]}"
        local band=$(get_frequency_band ${preferred_frequencies[$best_candidate_index]})
        log "Selected from preferred band: $selected_bssid with signal ${preferred_signals[$best_candidate_index]} dBm on $band"
        log "DEBUG: Current BSSID from wpa_cli: $current_bssid, Selected BSSID: $selected_bssid"
    else
        log "No preferred band candidates, selecting best signal overall"
        # Select best signal from all available
        local best_signal=${available_signals[0]}
        local best_available_index=0
        for i in "${!available_signals[@]}"; do
            if [[ ${available_signals[$i]} -gt $best_signal ]]; then
                best_signal=${available_signals[$i]}
                best_available_index=$i
            fi
        done
        selected_bssid="${available_bssids[$best_available_index]}"
        local band=$(get_frequency_band ${available_frequencies[$best_available_index]})
        log "Selected best overall: $selected_bssid with signal ${available_signals[$best_available_index]} dBm on $band"
        log "DEBUG: Current BSSID from wpa_cli: $current_bssid, Selected BSSID: $selected_bssid"
    fi
    
    echo "$selected_bssid"
}

# Connect to BSSID
connect_to_bssid() {
    local target_bssid="$1"
    
    log "DEBUG: connect_to_bssid called with target_bssid=$target_bssid"
    log "DEBUG: CURRENT_BSSID before comparison: $CURRENT_BSSID"
    
    if [[ "$CURRENT_BSSID" == "$target_bssid" ]]; then
        log "Already connected to $target_bssid, skipping roam"
        return 0
    fi
    
    # Use wpa_cli to roam
    if sudo wpa_cli -i "$INTERFACE" roam "$target_bssid" >/dev/null 2>&1; then
        if [[ -n "$CURRENT_BSSID" ]]; then
            log "Successfully roamed from $CURRENT_BSSID to $target_bssid"
        else
            log "Successfully connected to $target_bssid"
        fi
        CURRENT_BSSID="$target_bssid"
        
        # Verify the roam was successful by checking wpa_cli status
        sleep 2
        local actual_bssid=$(sudo wpa_cli -i "$INTERFACE" status | grep bssid | cut -d= -f2 | tr -d ' ')
        if [[ -n "$actual_bssid" && "$actual_bssid" != "00:00:00:00:00:00" ]]; then
            CURRENT_BSSID="$actual_bssid"
            log "Verified current BSSID: $CURRENT_BSSID"
        fi
        
        # Check and manage IP address after roam
        sleep 2  # Give the connection a moment to stabilize
        
        # Use the helper function to check and renew IP if needed
        if check_and_renew_ip "$INTERFACE"; then
            if [[ "$FIRST_CONNECTION" == "true" ]]; then
                log "First connection successful"
                FIRST_CONNECTION=false
            else
                log "Roam successful"
            fi
        else
            log "Warning: IP address management failed after roam"
        fi
        
        # Show updated network information after roam
        log "Network status after roam:"
        local ip_address=$(ip addr show "$INTERFACE" | grep -oP 'inet \K[0-9.]+' | head -1)
        local gateway=$(ip route | grep default | grep "$INTERFACE" | awk '{print $3}' | head -1)
        log "  IP address: ${ip_address:-'Not assigned'}"
        log "  Gateway: ${gateway:-'Not found'}"
        
        return 0
    else
        log "Failed to roam to $target_bssid"
        return 1
    fi
}

# Get random time between min and max
get_random_time() {
    local min="$1"
    local max="$2"
    echo $((RANDOM % (max - min + 1) + min))
}

# Display current network information
show_network_info() {
    log "Current network information:"
    
    # Show interface status
    local interface_status=$(ip link show "$INTERFACE" | grep -oP 'state \K\w+')
    log "  Interface $INTERFACE state: $interface_status"
    
    # Show IP address
    local ip_address=$(ip addr show "$INTERFACE" | grep -oP 'inet \K[0-9.]+' | head -1)
    if [[ -n "$ip_address" ]]; then
        log "  IP address: $ip_address"
        
        # Show subnet mask
        local subnet_mask=$(ip addr show "$INTERFACE" | grep -oP 'inet \K[0-9.]+/[0-9]+' | head -1)
        log "  Subnet: $subnet_mask"
    else
        log "  IP address: Not assigned"
    fi
    
    # Show gateway
    local gateway=$(ip route | grep default | grep "$INTERFACE" | awk '{print $3}' | head -1)
    if [[ -n "$gateway" ]]; then
        log "  Gateway: $gateway"
    else
        log "  Gateway: Not found"
    fi
    
    # Show DNS servers
    local dns_servers=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    if [[ -n "$dns_servers" ]]; then
        log "  DNS servers: $dns_servers"
    else
        log "  DNS servers: Not found"
    fi
    
    # Show current BSSID if connected
    local current_bssid=$(sudo wpa_cli -i "$INTERFACE" status | grep bssid | cut -d= -f2)
    if [[ -n "$current_bssid" && "$current_bssid" != "00:00:00:00:00:00" ]]; then
        log "  Current BSSID: $current_bssid"
    else
        log "  Current BSSID: Not connected"
    fi
}

# Create roam iteration separator
log_roam_separator() {
    ROAM_ITERATION=$((ROAM_ITERATION + 1))
    echo ""
    log "================================================================================="
    log "============================= ROAM ITERATION $ROAM_ITERATION ============================="
    log "================================================================================="
    echo ""
}

# Generate comprehensive frequency list for scanning
get_all_frequencies() {
    local frequencies=()
    
    # 2.4 GHz band (2400-2500 MHz)
    for freq in 2412 2417 2422 2427 2432 2437 2442 2447 2452 2457 2462 2467 2472 2484; do
        frequencies+=("$freq")
    done
    
    # 5 GHz band (5000-6000 MHz)
    for freq in 5180 5200 5220 5240 5260 5280 5300 5320 5500 5520 5540 5560 5580 5600 5620 5640 5660 5680 5700 5720 5745 5765 5785 5805 5825; do
        frequencies+=("$freq")
    done
    
    # 6 GHz band (6000-7000 MHz)
    for freq in 5955 5975 5995 6015 6035 6055 6075 6095 6115 6135 6155 6175 6195 6215 6235 6255 6275 6295 6315 6335 6355 6375 6395 6415 6435 6455 6475 6495 6515 6535 6555 6575 6595 6615 6635 6655 6675 6695 6715 6735 6755 6775 6795 6815 6835 6855 6875 6895 6915 6935 6955 6975 6995 7015 7035 7055 7075 7095 7115; do
        frequencies+=("$freq")
    done
    
    echo "${frequencies[@]}"
}

# Comprehensive frequency-specific scanning
comprehensive_scan() {
    local target_ssid="$1"
    log "Starting comprehensive scan for SSID: $target_ssid"
    
    # Use iw to scan all frequencies at once (much faster)
    log "Scanning all frequencies simultaneously..."
    local iw_scan_results=$(sudo iw dev "$INTERFACE" scan 2>/dev/null)
    
    if [[ -z "$iw_scan_results" ]]; then
        log "No scan results from iw command, falling back to wpa_cli"
        # Fallback to original wpa_cli method
        scan_for_ssid
        return
    fi
    
    # Parse iw results for target SSID using a more robust approach
    local found_bssids=()
    local found_signals=()
    local found_frequencies=()
    
    log "Processing iw scan results for SSID: $target_ssid"
    
    # Method 1: Parse BSS blocks that contain the target SSID
    local current_bssid=""
    local current_signal=""
    local current_freq=""
    local current_ssid=""
    local in_target_ssid_block=false
    
    while IFS= read -r line; do
        # Start of a new BSS block
        if [[ "$line" =~ ^BSS[[:space:]]+([0-9a-fA-F:]+) ]]; then
            # Save previous BSSID if it was for our target SSID
            if [[ "$in_target_ssid_block" == "true" && -n "$current_bssid" && -n "$current_signal" && -n "$current_freq" ]]; then
                found_bssids+=("$current_bssid")
                found_signals+=("$current_signal")
                found_frequencies+=("$current_freq")
                local band=$(get_frequency_band $current_freq)
                log "  Found BSSID: $current_bssid, Signal: $current_signal dBm, Frequency: $current_freq MHz, Band: $band"
            fi
            
            # Start new BSSID
            current_bssid="${BASH_REMATCH[1]}"
            current_signal=""
            current_freq=""
            current_ssid=""
            in_target_ssid_block=false
            
        elif [[ "$line" =~ signal:[[:space:]]+([0-9.-]+) ]]; then
            current_signal="${BASH_REMATCH[1]}"
            # Convert to integer (remove decimal part)
            current_signal=$(echo "$current_signal" | cut -d. -f1)
            
        elif [[ "$line" =~ freq:[[:space:]]+([0-9]+) ]]; then
            current_freq="${BASH_REMATCH[1]}"
            
        elif [[ "$line" =~ SSID:[[:space:]]+(.+) ]]; then
            current_ssid="${BASH_REMATCH[1]}"
            # Remove quotes if present
            current_ssid=$(echo "$current_ssid" | sed 's/^"//;s/"$//')
            if [[ "$current_ssid" == "$target_ssid" ]]; then
                in_target_ssid_block=true
                log "  Found target SSID '$target_ssid' for BSSID: $current_bssid"
            fi
        fi
    done <<< "$iw_scan_results"
    
    # Don't forget the last BSSID
    if [[ "$in_target_ssid_block" == "true" && -n "$current_bssid" && -n "$current_signal" && -n "$current_freq" ]]; then
        found_bssids+=("$current_bssid")
        found_signals+=("$current_signal")
        found_frequencies+=("$current_freq")
        local band=$(get_frequency_band $current_freq)
        log "  Found BSSID: $current_bssid, Signal: $current_signal dBm, Frequency: $current_freq MHz, Band: $band"
    fi
    
    # Method 2: Alternative parsing using grep and awk for any missed BSSIDs
    log "Additional BSSID extraction using alternative method..."
    local alt_bssids=$(echo "$iw_scan_results" | awk '
        /^BSS/ { bssid = $2; signal = ""; freq = ""; ssid = ""; next }
        /signal:/ { signal = $2; gsub(/\.00$/, "", signal); next }
        /freq:/ { freq = $2; next }
        /SSID:/ { ssid = $2; gsub(/^"/, "", ssid); gsub(/"$/, "", ssid); next }
        /^$/ { 
            if (ssid == "'"$target_ssid"'" && bssid != "" && signal != "" && freq != "") {
                print bssid " " signal " " freq
            }
            bssid = ""; signal = ""; freq = ""; ssid = ""
        }
        END {
            if (ssid == "'"$target_ssid"'" && bssid != "" && signal != "" && freq != "") {
                print bssid " " signal " " freq
            }
        }
    ')
    
    # Add any BSSIDs found by alternative method that we don't already have
    while IFS=' ' read -r bssid signal freq; do
        if [[ -n "$bssid" && -n "$signal" && -n "$freq" ]]; then
            # Check if we already have this BSSID
            local already_found=false
            for existing_bssid in "${found_bssids[@]}"; do
                if [[ "$existing_bssid" == "$bssid" ]]; then
                    already_found=true
                    break
                fi
            done
            
            if [[ "$already_found" == "false" ]]; then
                found_bssids+=("$bssid")
                found_signals+=("$signal")
                found_frequencies+=("$freq")
                local band=$(get_frequency_band $freq)
                log "  Found additional BSSID: $bssid, Signal: $signal dBm, Frequency: $freq MHz, Band: $band"
            fi
        fi
    done <<< "$alt_bssids"
    
    # Method 3: Direct grep approach as final fallback
    log "Final BSSID extraction using direct grep method..."
    local direct_bssids=$(echo "$iw_scan_results" | grep -A 50 "SSID: $target_ssid" | grep "^BSS" | awk '{print $2}' | sort -u)
    
    while IFS= read -r bssid; do
        if [[ -n "$bssid" ]]; then
            # Check if we already have this BSSID
            local already_found=false
            for existing_bssid in "${found_bssids[@]}"; do
                if [[ "$existing_bssid" == "$bssid" ]]; then
                    already_found=true
                    break
                fi
            done
            
            if [[ "$already_found" == "false" ]]; then
                # Find signal and frequency for this BSSID
                local signal=$(echo "$iw_scan_results" | grep -A 20 "BSS $bssid" | grep "signal:" | head -1 | awk '{print $2}' | cut -d. -f1)
                local freq=$(echo "$iw_scan_results" | grep -A 20 "BSS $bssid" | grep "freq:" | head -1 | awk '{print $2}')
                
                if [[ -n "$signal" && -n "$freq" ]]; then
                    found_bssids+=("$bssid")
                    found_signals+=("$signal")
                    found_frequencies+=("$freq")
                    local band=$(get_frequency_band $freq)
                    log "  Found additional BSSID via direct method: $bssid, Signal: $signal dBm, Frequency: $freq MHz, Band: $band"
                fi
            fi
        fi
    done <<< "$direct_bssids"
    
    log "Comprehensive scan completed. Found ${#found_bssids[@]} BSSIDs for SSID '$target_ssid'"
    
    # Update global scan results with comprehensive findings
    if [[ ${#found_bssids[@]} -gt 0 ]]; then
        scan_results="bssid	frequency	signal level	flags	ssid"
        for i in "${!found_bssids[@]}"; do
            scan_results+=$'\n'"${found_bssids[$i]}	${found_frequencies[$i]}	${found_signals[$i]}	[WPA2-PSK-CCMP][ESS]	$target_ssid"
        done
    else
        log "No BSSIDs found, falling back to wpa_cli scan"
        scan_for_ssid
    fi
}

# Debug function to check for all BSSIDs of target SSID
debug_ssid_bssids() {
    local target_ssid="$1"
    log "DEBUG: Checking for all BSSIDs of SSID '$target_ssid' using alternative method..."
    
    # Show raw iw scan output for debugging
    log "Raw iw scan output (first 50 lines):"
    local raw_scan=$(sudo iw dev "$INTERFACE" scan 2>/dev/null | head -50)
    echo "$raw_scan" | while IFS= read -r line; do
        log "  RAW: $line"
    done
    
    # Try using iw command as alternative
    if command -v iw >/dev/null 2>&1; then
        log "Using 'iw' command to scan for SSID..."
        local iw_results=$(sudo iw dev "$INTERFACE" scan | grep -A 20 -B 5 "SSID: $target_ssid" 2>/dev/null || true)
        if [[ -n "$iw_results" ]]; then
            log "iw scan results for '$target_ssid':"
            echo "$iw_results" | while IFS= read -r line; do
                log "  $line"
            done
        else
            log "No results found using iw command"
        fi
    fi
    
    # Also try nmcli if available
    if command -v nmcli >/dev/null 2>&1; then
        log "Using 'nmcli' command to scan for SSID..."
        local nmcli_results=$(nmcli dev wifi list | grep "$target_ssid" 2>/dev/null || true)
        if [[ -n "$nmcli_results" ]]; then
            log "nmcli scan results for '$target_ssid':"
            echo "$nmcli_results" | while IFS= read -r line; do
                log "  $line"
            done
        else
            log "No results found using nmcli command"
        fi
    fi
}

# Main roaming loop
roam_loop() {
    log "Starting roaming loop..."
    
    while true; do
        # Create roam iteration separator
        log_roam_separator
        
        # Comprehensive frequency-specific scan
        comprehensive_scan "$SSID_Name"
        debug_ssid_bssids "$SSID_Name"
        get_bssids "$SSID_Name" "$Min_Signal"
        
        # If only one BSSID, don't roam
        if [[ ${#BSSIDS[@]} -eq 1 ]]; then
            log "Only one BSSID available, connecting without roaming"
            connect_to_bssid "${BSSIDS[0]}"
        else
            # Select a different BSSID to roam to (not the current one)
            local target_bssid=$(select_different_bssid)
            if [[ -n "$target_bssid" ]]; then
                # Update CURRENT_BSSID before calling connect_to_bssid to ensure accurate comparison
                CURRENT_BSSID=$(sudo wpa_cli -i "$INTERFACE" status | grep bssid | cut -d= -f2 | tr -d ' ')
                if [[ -z "$CURRENT_BSSID" || "$CURRENT_BSSID" == "00:00:00:00:00:00" ]]; then
                    CURRENT_BSSID=""
                fi
                
                if [[ -n "$CURRENT_BSSID" ]]; then
                    log "Roaming from $CURRENT_BSSID to BSSID: $target_bssid"
                else
                    log "Connecting to BSSID: $target_bssid"
                fi
                connect_to_bssid "$target_bssid"
            else
                log "No suitable different BSSID found for roaming"
            fi
        fi
        
        # Wait for random time before next roam
        local wait_time=$(get_random_time "$Min_Time_Roam" "$Max_Time_Roam")
        log "Waiting $wait_time minutes before next roam..."
        sleep $((wait_time * 60))
    done
}

# Main function
main() {
    log "Starting WiFi roaming script"
    
    # Check if running as root for log file access
    if [[ $EUID -ne 0 ]]; then
        log "This script requires root privileges for logging and network operations"
        log "Please run with sudo"
        exit 1
    fi
    
    # Check and install required tools
    check_required_tools
    
    # Load parameters
    load_parameters
    
    # Detect wireless interface
    detect_wireless_interface
    
    # Initialize current BSSID
    CURRENT_BSSID=$(sudo wpa_cli -i "$INTERFACE" status | grep bssid | cut -d= -f2 | tr -d ' ')
    if [[ -z "$CURRENT_BSSID" || "$CURRENT_BSSID" == "00:00:00:00:00:00" ]]; then
        CURRENT_BSSID=""
        log "Not currently connected to any BSSID"
    else
        log "Current BSSID: $CURRENT_BSSID"
    fi
    
    # Show initial network information
    show_network_info
    
    # Start roaming loop
    roam_loop
}

# Run main function
main "$@"

