#!/bin/bash

# Custom Ubuntu ISO Builder for WiFi Roaming System
# This script creates a custom Ubuntu Server ISO with embedded WiFi roaming scripts
# and offline package installation capabilities

set -euo pipefail

# Configuration
UBUNTU_VERSION="24.04.3"
UBUNTU_ISO_NAME="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
UBUNTU_ISO_URL="https://releases.ubuntu.com/24.04/${UBUNTU_ISO_NAME}"
CUSTOM_ISO_NAME="ubuntu-${UBUNTU_VERSION}-wifi-roaming-server.iso"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/iso-build"
ISO_EXTRACT_DIR="${WORK_DIR}/iso-extracted"
ISO_NEW_DIR="${WORK_DIR}/iso-new"
CUSTOM_ISO_DIR="${SCRIPT_DIR}/custom-iso"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    local required_tools=("xorriso" "wget" "7z" "unsquashfs" "mksquashfs" "genisoimage")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Installing missing tools..."
        
        # Update package list
        sudo apt-get update
        
        # Install missing tools
        local packages=()
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "xorriso") packages+=("xorriso") ;;
                "7z") packages+=("p7zip-full") ;;
                "unsquashfs"|"mksquashfs") packages+=("squashfs-tools") ;;
                "genisoimage") packages+=("genisoimage") ;;
                *) packages+=("$tool") ;;
            esac
        done
        
        sudo apt-get install -y "${packages[@]}"
        log_success "Required tools installed"
    else
        log_success "All prerequisites satisfied"
    fi
}

# Function to download Ubuntu ISO
download_ubuntu_iso() {
    log_info "Checking for Ubuntu ISO..."
    
    if [ -f "${WORK_DIR}/${UBUNTU_ISO_NAME}" ]; then
        log_success "Ubuntu ISO already exists: ${UBUNTU_ISO_NAME}"
        return 0
    fi
    
    log_info "Downloading Ubuntu ${UBUNTU_VERSION} ISO..."
    mkdir -p "$WORK_DIR"
    
    if wget -O "${WORK_DIR}/${UBUNTU_ISO_NAME}" "$UBUNTU_ISO_URL"; then
        log_success "Ubuntu ISO downloaded successfully"
    else
        log_error "Failed to download Ubuntu ISO"
        exit 1
    fi
}

# Function to extract Ubuntu ISO
extract_iso() {
    log_info "Extracting Ubuntu ISO..."
    
    # Clean up previous extraction
    [ -d "$ISO_EXTRACT_DIR" ] && rm -rf "$ISO_EXTRACT_DIR"
    [ -d "$ISO_NEW_DIR" ] && rm -rf "$ISO_NEW_DIR"
    
    mkdir -p "$ISO_EXTRACT_DIR"
    mkdir -p "$ISO_NEW_DIR"
    
    # Extract the ISO
    log_info "Extracting ISO using 7z..."
    if ! 7z x -o"$ISO_EXTRACT_DIR" "${WORK_DIR}/${UBUNTU_ISO_NAME}"; then
        log_error "Failed to extract ISO with 7z"
        exit 1
    fi
    
    # Verify extraction worked
    if [ ! -d "$ISO_EXTRACT_DIR" ] || [ -z "$(ls -A "$ISO_EXTRACT_DIR" 2>/dev/null)" ]; then
        log_error "ISO extraction failed - directory is empty or doesn't exist"
        exit 1
    fi
    
    # Copy extracted contents to new ISO directory
    log_info "Copying extracted contents..."
    if ! cp -r "$ISO_EXTRACT_DIR"/* "$ISO_NEW_DIR"/; then
        log_error "Failed to copy extracted contents"
        exit 1
    fi
    
    # Verify copy worked
    if [ -z "$(ls -A "$ISO_NEW_DIR" 2>/dev/null)" ]; then
        log_error "Copy failed - new ISO directory is empty"
        exit 1
    fi
    
    # Make files writable
    chmod -R u+w "$ISO_NEW_DIR"
    
    # Show what was extracted for debugging
    log_info "Extraction verification:"
    log_info "Files in ISO_NEW_DIR: $(ls -1 "$ISO_NEW_DIR" | wc -l) items"
    log_info "Directory structure preview:"
    find "$ISO_NEW_DIR" -maxdepth 2 -type d | head -10 || true
    
    log_success "ISO extracted successfully"
}

# Function to customize the filesystem
customize_filesystem() {
    log_info "Customizing filesystem..."
    
    local squashfs_file="${ISO_NEW_DIR}/casper/filesystem.squashfs"
    local filesystem_dir="${WORK_DIR}/filesystem"
    
    # Check if squashfs file exists
    if [ ! -f "$squashfs_file" ]; then
        log_error "Squashfs file not found at: $squashfs_file"
        log_info "Searching for squashfs files in extracted ISO..."
        
        # Search for squashfs files - prioritize filesystem over installer
        log_info "Available squashfs files:"
        find "$ISO_NEW_DIR" -name "*.squashfs" -type f 2>/dev/null | while read -r file; do
            log_info "  - $(basename "$file")"
        done
        
        # Look for the main filesystem squashfs (not installer)
        local found_squashfs=""
        local all_squashfs
        all_squashfs=$(find "$ISO_NEW_DIR" -name "*.squashfs" -type f 2>/dev/null)
        
        # Priority order: filesystem.squashfs > any file without "installer" in name > any squashfs
        for file in $all_squashfs; do
            if [[ "$(basename "$file")" == "filesystem.squashfs" ]]; then
                found_squashfs="$file"
                break
            fi
        done
        
        # If no filesystem.squashfs, look for non-installer squashfs
        if [ -z "$found_squashfs" ]; then
            for file in $all_squashfs; do
                if [[ "$(basename "$file")" != *"installer"* ]]; then
                    found_squashfs="$file"
                    break
                fi
            done
        fi
        
        # If still nothing, look for any squashfs that might contain a root filesystem
        if [ -z "$found_squashfs" ]; then
            for file in $all_squashfs; do
                # Check if this squashfs contains /bin/bash or /usr/bin/bash
                log_info "Testing squashfs file: $(basename "$file")"
                if unsquashfs -l "$file" 2>/dev/null | grep -q "bin/bash"; then
                    log_info "  - Contains bash, likely a root filesystem"
                    found_squashfs="$file"
                    break
                else
                    log_info "  - No bash found, likely installer/live system"
                fi
            done
        fi
        
        # Final fallback - use any squashfs file
        if [ -z "$found_squashfs" ]; then
            found_squashfs=$(echo "$all_squashfs" | head -1)
        fi
        
        if [ -n "$found_squashfs" ]; then
            log_info "Selected squashfs file: $(basename "$found_squashfs")"
            squashfs_file="$found_squashfs"
        else
            log_error "No squashfs files found in the extracted ISO"
            log_info "ISO directory structure:"
            find "$ISO_NEW_DIR" -maxdepth 3 -type d 2>/dev/null || true
            log_info "Files in potential casper location:"
            ls -la "$ISO_NEW_DIR/casper/" 2>/dev/null || log_warning "No casper directory found"
            exit 1
        fi
    fi
    
    # Extract squashfs
    log_info "Extracting squashfs filesystem from: $squashfs_file"
    [ -d "$filesystem_dir" ] && sudo rm -rf "$filesystem_dir"
    mkdir -p "$filesystem_dir"
    
    sudo unsquashfs -d "$filesystem_dir" "$squashfs_file"
    
    # Mount necessary filesystems for chroot
    log_info "Preparing chroot environment..."
    
    # Ensure mount point directories exist
    sudo mkdir -p "$filesystem_dir/dev"
    sudo mkdir -p "$filesystem_dir/dev/pts"
    sudo mkdir -p "$filesystem_dir/proc"
    sudo mkdir -p "$filesystem_dir/sys"
    
    # Mount the filesystems
    sudo mount --bind /dev "$filesystem_dir/dev"
    sudo mount --bind /dev/pts "$filesystem_dir/dev/pts"
    sudo mount --bind /proc "$filesystem_dir/proc"
    sudo mount --bind /sys "$filesystem_dir/sys"
    
    # Set up networking for chroot
    log_info "Configuring network access for chroot..."
    sudo cp /etc/resolv.conf "$filesystem_dir/etc/resolv.conf" 2>/dev/null || true
    sudo cp /etc/hosts "$filesystem_dir/etc/hosts" 2>/dev/null || true
    
    # Verify chroot environment is valid
    log_info "Verifying chroot environment..."
    if [ ! -f "$filesystem_dir/bin/bash" ] && [ ! -f "$filesystem_dir/usr/bin/bash" ]; then
        log_error "No bash found in extracted filesystem"
        log_info "Filesystem contents:"
        ls -la "$filesystem_dir/" | head -10
        log_info "Checking for shells:"
        find "$filesystem_dir" -name "*sh" -type f | head -5
        exit 1
    fi
    
    # Determine the correct bash path
    local bash_path="/bin/bash"
    if [ ! -f "$filesystem_dir/bin/bash" ] && [ -f "$filesystem_dir/usr/bin/bash" ]; then
        bash_path="/usr/bin/bash"
    fi
    log_info "Using bash at: $bash_path"
    
    # Update package repositories and install required packages
    log_info "Installing required packages in chroot..."
    sudo chroot "$filesystem_dir" "$bash_path" -c "
        export DEBIAN_FRONTEND=noninteractive
        echo 'Updating package lists...'
        apt-get update
        echo 'Installing required packages...'
        apt-get install -y wpasupplicant dhcpcd5 iw wireless-tools speedtest-cli curl wget systemd
        echo 'Cleaning up...'
        apt-get clean
        rm -rf /var/lib/apt/lists/*
        echo 'Package installation completed'
    "
    
    # Create necessary directories
    log_info "Creating directories and copying files..."
    sudo mkdir -p "$filesystem_dir/opt/wifi-roam"
    sudo mkdir -p "$filesystem_dir/var/log/wifi-roam"
    
    # Copy WiFi roaming scripts
    sudo cp "$CUSTOM_ISO_DIR"/wifi-roam/* "$filesystem_dir/opt/wifi-roam/"
    sudo chmod +x "$filesystem_dir"/opt/wifi-roam/*.sh
    
    # Create the first-boot service
    log_info "Creating first-boot service..."
    sudo tee "$filesystem_dir/etc/systemd/system/wifi-roam-firstboot.service" > /dev/null << 'EOF'
[Unit]
Description=WiFi Roaming First Boot Setup
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=/opt/wifi-roam/wifi_roam_setup.sh /opt/wifi-roam/parameters.txt
RemainAfterExit=yes
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable the service
    sudo chroot "$filesystem_dir" systemctl enable wifi-roam-firstboot.service
    
    # Unmount filesystems
    log_info "Cleaning up chroot environment..."
    sudo umount "$filesystem_dir/sys" 2>/dev/null || true
    sudo umount "$filesystem_dir/proc" 2>/dev/null || true
    sudo umount "$filesystem_dir/dev/pts" 2>/dev/null || true
    sudo umount "$filesystem_dir/dev" 2>/dev/null || true
    
    # Rebuild squashfs
    log_info "Rebuilding squashfs filesystem..."
    sudo rm "$squashfs_file"
    sudo mksquashfs "$filesystem_dir" "$squashfs_file" -comp xz
    
    # Clean up
    sudo rm -rf "$filesystem_dir"
    
    log_success "Filesystem customized successfully"
}

# Function to add autoinstall configuration
add_autoinstall_config() {
    log_info "Adding autoinstall configuration..."
    
    # Copy autoinstall files to ISO
    cp "$CUSTOM_ISO_DIR/user-data" "$ISO_NEW_DIR/"
    cp "$CUSTOM_ISO_DIR/meta-data" "$ISO_NEW_DIR/"
    
    # Copy WiFi roaming scripts to ISO root (for late-commands)
    mkdir -p "$ISO_NEW_DIR/wifi-roam"
    cp "$CUSTOM_ISO_DIR"/wifi-roam/* "$ISO_NEW_DIR/wifi-roam/"
    
    log_success "Autoinstall configuration added"
}

# Function to update GRUB configuration
update_grub_config() {
    log_info "Updating GRUB configuration..."
    
    # Backup original grub.cfg
    [ -f "$ISO_NEW_DIR/boot/grub/grub.cfg" ] && cp "$ISO_NEW_DIR/boot/grub/grub.cfg" "$ISO_NEW_DIR/boot/grub/grub.cfg.backup"
    
    # Copy our custom grub configuration
    cp "$CUSTOM_ISO_DIR/grub.cfg" "$ISO_NEW_DIR/boot/grub/grub.cfg"
    
    log_success "GRUB configuration updated"
}

# Function to create the new ISO
create_custom_iso() {
    log_info "Creating custom ISO..."
    
    local output_iso="${SCRIPT_DIR}/${CUSTOM_ISO_NAME}"
    
    # Remove existing custom ISO
    [ -f "$output_iso" ] && rm "$output_iso"
    
    # Create the new ISO
    cd "$ISO_NEW_DIR"
    
    # Comprehensive boot file detection for all Ubuntu versions
    log_info "Detecting boot configuration for Ubuntu ${UBUNTU_VERSION}..."
    
    # First, check if we have actual bootable files (not just directories)
    local has_bootable_files=false
    
    # Check for actual boot files, not just directories
    if [ -f "boot/grub/efi.img" ] || [ -f "EFI/boot/bootx64.efi" ] || [ -f "isolinux/isolinux.bin" ] || [ -f "boot/isolinux/isolinux.bin" ]; then
        has_bootable_files=true
    fi
    
    if [ "$has_bootable_files" = false ]; then
        log_warning "No bootable files found in extracted ISO"
        
        # Debug: Show what's actually in the boot directories
        log_info "Debugging boot directory contents:"
        [ -d "boot" ] && log_info "Contents of /boot:" && find boot -type f | head -10 | while read -r f; do log_info "  $f"; done
        [ -d "EFI" ] && log_info "Contents of /EFI:" && find EFI -type f | head -10 | while read -r f; do log_info "  $f"; done
        [ -d "isolinux" ] && log_info "Contents of /isolinux:" && find isolinux -type f | head -10 | while read -r f; do log_info "  $f"; done
        
        log_info "Extracting boot files from original Ubuntu ISO..."
        
        local original_iso="${WORK_DIR}/${UBUNTU_ISO_NAME}"
        local temp_mount="/tmp/ubuntu_iso_mount_$$"
        
        mkdir -p "$temp_mount"
        if sudo mount -o loop,ro "$original_iso" "$temp_mount" 2>/dev/null; then
            log_info "Copying boot files from original Ubuntu ISO..."
            
            # Copy all potential boot directories
            [ -d "$temp_mount/boot" ] && sudo cp -r "$temp_mount/boot" . && log_info "  ✓ Copied /boot directory"
            [ -d "$temp_mount/EFI" ] && sudo cp -r "$temp_mount/EFI" . && log_info "  ✓ Copied /EFI directory"
            [ -d "$temp_mount/isolinux" ] && sudo cp -r "$temp_mount/isolinux" . && log_info "  ✓ Copied /isolinux directory"
            [ -d "$temp_mount/.disk" ] && sudo cp -r "$temp_mount/.disk" . && log_info "  ✓ Copied /.disk directory"
            
            # Copy individual boot files that might be at root level
            for file in "$temp_mount"/*.cfg "$temp_mount"/*.c32 "$temp_mount"/vmlinuz* "$temp_mount"/initrd*; do
                [ -f "$file" ] && sudo cp "$file" . && log_info "  ✓ Copied $(basename "$file")"
            done
            
            sudo umount "$temp_mount" 2>/dev/null || true
            rmdir "$temp_mount" 2>/dev/null || true
            
            log_success "Boot files extracted from original ISO"
        else
            log_error "Failed to mount original ISO for boot file extraction"
            rmdir "$temp_mount" 2>/dev/null || true
        fi
    fi
    
    # Now detect boot files comprehensively
    local isolinux_bin=""
    local boot_cat=""
    local efi_img=""
    
    # Enhanced isolinux detection
    local isolinux_paths=(
        "isolinux/isolinux.bin"
        "boot/isolinux/isolinux.bin" 
        "syslinux/isolinux.bin"
        "isolinux.bin"
    )
    
    for path in "${isolinux_paths[@]}"; do
        if [ -f "$path" ]; then
            isolinux_bin="$path"
            boot_cat="$(dirname "$path")/boot.cat"
            [ ! -f "$boot_cat" ] && boot_cat="isolinux/boot.cat"  # fallback
            break
        fi
    done
    
    # Enhanced EFI detection  
    local efi_paths=(
        "boot/grub/efi.img"
        "EFI/boot/bootx64.efi"
        "EFI/boot/grubx64.efi" 
        "boot/efi.img"
        "efi.img"
    )
    
    for path in "${efi_paths[@]}"; do
        if [ -f "$path" ]; then
            efi_img="$path"
            break
        fi
    done
    
    log_info "Boot files detected:"
    log_info "  Isolinux: ${isolinux_bin:-not found}"
    log_info "  EFI: ${efi_img:-not found}"
    
    # Create ISO with appropriate boot options
    if [ -n "$isolinux_bin" ] && [ -n "$efi_img" ]; then
        # Dual boot (BIOS + UEFI)
        log_info "Creating hybrid BIOS/UEFI bootable ISO..."
        log_info "  Using BIOS boot: $isolinux_bin"
        log_info "  Using UEFI boot: $efi_img"
        
        # Enhanced hybrid boot parameters for Ubuntu 24.04.3
        local hybrid_params=()
        hybrid_params+=(-r -V "WiFi-Roaming-Ubuntu-${UBUNTU_VERSION}")
        hybrid_params+=(-J -joliet-long)
        hybrid_params+=(-cache-inodes)
        
        # BIOS boot configuration
        hybrid_params+=(-b "$isolinux_bin")
        hybrid_params+=(-c "$boot_cat")
        hybrid_params+=(-no-emul-boot)
        hybrid_params+=(-boot-load-size 4)
        hybrid_params+=(-boot-info-table)
        
        # UEFI boot configuration
        hybrid_params+=(-eltorito-alt-boot)
        hybrid_params+=(-e "$efi_img")
        hybrid_params+=(-no-emul-boot)
        
        # Hybrid MBR/GPT support
        hybrid_params+=(-isohybrid-gpt-basdat)
        hybrid_params+=(-isohybrid-apm-hfsplus)
        
        log_info "xorriso parameters: ${hybrid_params[*]} -o $output_iso ."
        xorriso -as mkisofs "${hybrid_params[@]}" -o "$output_iso" .
            
    elif [ -n "$efi_img" ]; then
        # UEFI only - MATCH ORIGINAL UBUNTU ISO EXACTLY
        log_info "Creating UEFI-only bootable ISO (matching original Ubuntu structure)..."
        log_info "  Using UEFI boot: $efi_img"
        
        # CRITICAL: Use the EXACT same xorriso command as Ubuntu's official build
        # No extra parameters that create additional boot catalog entries
        log_info "Using minimal xorriso parameters to match original Ubuntu ISO"
        
        xorriso -as mkisofs \
            -r -V "Ubuntu-Server ${UBUNTU_VERSION} LTS amd64" \
            -o "$output_iso" \
            -J -l \
            -c isolinux/boot.cat \
            -eltorito-alt-boot \
            -e "$efi_img" \
            -no-emul-boot \
            .
            
        # Verify no extra boot files were created
        log_info "Verifying ISO structure matches original..."
        
        # Mount and check our created ISO
        local temp_check="/tmp/iso_check_$$"
        mkdir -p "$temp_check"
        if sudo mount -o loop,ro "$output_iso" "$temp_check" 2>/dev/null; then
            local boot_files=$(find "$temp_check" -name "*.img" | wc -l)
            local efi_files=$(find "$temp_check/EFI" -name "*.efi" 2>/dev/null | wc -l)
            
            sudo umount "$temp_check" 2>/dev/null
            rmdir "$temp_check"
            
            log_info "Boot structure check:"
            log_info "  Boot .img files found: $boot_files"
            log_info "  EFI .efi files found: $efi_files"
            
            if [ "$boot_files" -gt 1 ]; then
                log_warning "Extra boot files detected - this might cause UEFI boot issues"
            else
                log_success "Clean boot structure - matches original Ubuntu ISO"
            fi
        fi
        
    elif [ -n "$isolinux_bin" ]; then
        # BIOS only
        log_info "Creating BIOS-only bootable ISO..."
        log_info "  Using BIOS boot: $isolinux_bin"
        
        xorriso -as mkisofs \
            -r -V "WiFi Roaming Ubuntu ${UBUNTU_VERSION}" \
            -J -l -b "$isolinux_bin" \
            -c "$boot_cat" \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            -o "$output_iso" \
            .
    else
        # Last resort: Try to make it bootable anyway by analyzing the directory structure
        log_error "No standard boot files detected"
        log_info "Analyzing directory structure for alternative boot methods..."
        
        # List what we actually have
        log_info "Available directories:"
        find . -maxdepth 2 -type d | head -10 | while read -r dir; do
            log_info "  $dir"
        done
        
        log_info "Available boot-related files:"
        find . -maxdepth 3 \( -name "*.efi" -o -name "*.img" -o -name "*.bin" -o -name "grub*" \) -type f | head -10 | while read -r file; do
            log_info "  $file"
        done
        
        log_error "Cannot create bootable ISO - no valid boot configuration found"
        log_error "This indicates an issue with the Ubuntu ${UBUNTU_VERSION} ISO structure"
        exit 1
    fi
    
    cd - > /dev/null
    
    if [ -f "$output_iso" ]; then
        log_success "Custom ISO created successfully: $output_iso"
        
        # Display ISO information
        local iso_size
        iso_size=$(du -h "$output_iso" | cut -f1)
        log_info "ISO size: $iso_size"
        log_info "ISO location: $output_iso"
    else
        log_error "Failed to create custom ISO"
        exit 1
    fi
}

# Function to cleanup
cleanup() {
    log_info "Cleaning up temporary files..."
    
    # Unmount any remaining mounts
    if mountpoint -q "${WORK_DIR}/filesystem/sys" 2>/dev/null; then
        sudo umount "${WORK_DIR}/filesystem/sys" || true
    fi
    if mountpoint -q "${WORK_DIR}/filesystem/proc" 2>/dev/null; then
        sudo umount "${WORK_DIR}/filesystem/proc" || true
    fi
    if mountpoint -q "${WORK_DIR}/filesystem/dev/pts" 2>/dev/null; then
        sudo umount "${WORK_DIR}/filesystem/dev/pts" || true
    fi
    if mountpoint -q "${WORK_DIR}/filesystem/dev" 2>/dev/null; then
        sudo umount "${WORK_DIR}/filesystem/dev" || true
    fi
    
    # Remove temporary directories (keep the downloaded ISO)
    [ -d "$ISO_EXTRACT_DIR" ] && rm -rf "$ISO_EXTRACT_DIR"
    [ -d "$ISO_NEW_DIR" ] && rm -rf "$ISO_NEW_DIR"
    [ -d "${WORK_DIR}/filesystem" ] && sudo rm -rf "${WORK_DIR}/filesystem"
    
    log_success "Cleanup completed"
}

# Function to show usage
show_usage() {
    echo "Custom Ubuntu ISO Builder for WiFi Roaming System"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --clean        Clean up all temporary files and exit"
    echo ""
    echo "This script will:"
    echo "  1. Download Ubuntu Server $UBUNTU_VERSION ISO"
    echo "  2. Extract and customize the filesystem with required packages"
    echo "  3. Add WiFi roaming scripts and autoinstall configuration"
    echo "  4. Create a custom ISO with automated installation"
    echo ""
    echo "Prerequisites:"
    echo "  - Root/sudo access"
    echo "  - Internet connection for downloading"
    echo "  - At least 8GB free disk space"
}

# Main function
main() {
    # Handle command line arguments
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        --clean)
            cleanup
            exit 0
            ;;
        "")
            # Continue with normal execution
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    
    log_info "Starting custom Ubuntu ISO build process..."
    log_info "Target: Ubuntu Server $UBUNTU_VERSION with WiFi roaming capabilities"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Execute build steps
    check_prerequisites
    download_ubuntu_iso
    extract_iso
    customize_filesystem
    add_autoinstall_config
    update_grub_config
    create_custom_iso
    
    # Success message
    echo ""
    log_success "Custom Ubuntu ISO build completed successfully!"
    echo ""
    log_info "=== Build Summary ==="
    log_info "Custom ISO: ${SCRIPT_DIR}/${CUSTOM_ISO_NAME}"
    log_info "Features:"
    log_info "  ✓ Fully automated installation (no user interaction)"
    log_info "  ✓ Pre-installed WiFi packages: wpasupplicant, dhcpcd5, iw, wireless-tools"
    log_info "  ✓ Pre-installed speedtest-cli for network testing"
    log_info "  ✓ WiFi roaming scripts embedded and configured"
    log_info "  ✓ Automatic WiFi connection and roaming after installation"
    log_info "  ✓ Persistent services across reboots"
    echo ""
    log_info "=== Next Steps ==="
    log_info "1. Burn the ISO to USB/CD: dd if=${CUSTOM_ISO_NAME} of=/dev/sdX bs=4M"
    log_info "2. Boot the target system from the USB/CD"
    log_info "3. Select 'Install WiFi Roaming Ubuntu Server (Automated)'"
    log_info "4. Wait for installation to complete (no user input required)"
    log_info "5. System will reboot and automatically connect to WiFi"
    echo ""
    log_warning "Note: Make sure the target system has the WiFi hardware before installation"
}

# Run main function
main "$@"
