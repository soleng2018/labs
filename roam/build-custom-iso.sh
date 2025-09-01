#!/bin/bash

# Ubuntu 24.04.3 WiFi Roaming Custom ISO Builder  
# Creates a bootable Ubuntu Server ISO with embedded WiFi roaming capabilities
# Uses hybrid boot (legacy BIOS + UEFI) for maximum compatibility

set -e

# Configuration
UBUNTU_VERSION="24.04.3"
UBUNTU_ISO_NAME="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
UBUNTU_ISO_URL="https://releases.ubuntu.com/24.04/${UBUNTU_ISO_NAME}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get script directory and use relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/iso-exact"
ORIGINAL_ISO="$SCRIPT_DIR/iso-build/$UBUNTU_ISO_NAME"
CUSTOM_ISO="$SCRIPT_DIR/ubuntu-${UBUNTU_VERSION}-wifi-roaming-server-EXACT.iso"

# Verify required files exist
if [[ ! -f "$SCRIPT_DIR/parameters.txt" ]] || [[ ! -f "$SCRIPT_DIR/wpa_supplicant.conf" ]] || [[ ! -d "$SCRIPT_DIR/custom-iso" ]]; then
    log_error "Required WiFi roaming files not found in script directory: $SCRIPT_DIR"
    log_error "Please ensure the following files/directories exist:"
    log_error "  - parameters.txt"
    log_error "  - wpa_supplicant.conf" 
    log_error "  - *.sh scripts (roam_script.sh, speedtest_script.sh, wifi_roam_setup.sh)"
    log_error "  - custom-iso/ directory with user-data, meta-data, grub.cfg"
    exit 1
fi

cleanup() {
    sudo umount "$WORK_DIR/original" 2>/dev/null || true
    sudo umount "$WORK_DIR/custom" 2>/dev/null || true
    sudo umount "$WORK_DIR/filesystem"/{dev/pts,dev,proc,sys} 2>/dev/null || true
    sudo rm -rf "$WORK_DIR/original" "$WORK_DIR/custom" 2>/dev/null || true
}

trap cleanup EXIT

download_ubuntu_iso() {
    log_info "Checking for Ubuntu $UBUNTU_VERSION ISO..."
    
    # Create iso-build directory if it doesn't exist
    mkdir -p "$SCRIPT_DIR/iso-build"
    
    if [ ! -f "$ORIGINAL_ISO" ]; then
        log_info "Ubuntu ISO not found. Downloading from $UBUNTU_ISO_URL"
        log_warning "This will take several minutes depending on your internet connection..."
        
        # Download with progress
        if command -v wget >/dev/null 2>&1; then
            wget --progress=bar:force:noscroll -O "$ORIGINAL_ISO" "$UBUNTU_ISO_URL" || {
                log_error "Failed to download Ubuntu ISO"
                rm -f "$ORIGINAL_ISO"
                exit 1
            }
        elif command -v curl >/dev/null 2>&1; then
            curl -L --progress-bar -o "$ORIGINAL_ISO" "$UBUNTU_ISO_URL" || {
                log_error "Failed to download Ubuntu ISO"
                rm -f "$ORIGINAL_ISO"
                exit 1
            }
        else
            log_error "Neither wget nor curl found. Please install one of them."
            exit 1
        fi
        
        log_success "Ubuntu ISO downloaded successfully"
    else
        log_info "Ubuntu ISO already exists: $ORIGINAL_ISO"
    fi
    
    # Verify ISO integrity
    local iso_size=$(stat -c%s "$ORIGINAL_ISO" 2>/dev/null || echo "0")
    if [ "$iso_size" -lt 1000000000 ]; then  # Less than 1GB indicates incomplete download
        log_error "ISO file appears incomplete (size: $iso_size bytes). Removing and retrying..."
        rm -f "$ORIGINAL_ISO"
        download_ubuntu_iso  # Recursive call to retry
    else
        log_info "ISO file size looks good: $(du -h "$ORIGINAL_ISO" | cut -f1)"
    fi
}

main() {
    log_info "Starting EXACT boot structure copy approach for Ubuntu 24.04.3"
    
    # Download Ubuntu ISO if needed
    download_ubuntu_iso
    
    # Create work environment
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"/{original,custom,filesystem}
    cd "$WORK_DIR"
    
    # Method 1: Mount original ISO and copy EXACTLY
    log_info "Mounting original Ubuntu ISO..."
    sudo mount -o loop,ro "$ORIGINAL_ISO" original/
    
    log_info "Copying ENTIRE original ISO structure..."
    sudo cp -a original/* custom/
    sudo cp -a original/.??* custom/ 2>/dev/null || true
    
    log_info "Analyzing original boot structure..."
    find original -name "*.img" | while read -r file; do
        log_info "  Original boot file: $file"
    done
    
    # Unmount original (keep copy)
    sudo umount original/
    
    # Now we have an EXACT copy - modify ONLY the filesystem
    log_info "Extracting filesystem from exact copy..."
    
    # Find the main squashfs
    local squashfs_file=$(find custom/casper -name "*ubuntu-server-minimal.squashfs" | head -1)
    if [ -z "$squashfs_file" ]; then
        log_error "Could not find main squashfs file"
        exit 1
    fi
    
    log_info "Using squashfs: $squashfs_file"
    
    # Extract filesystem without modifying boot structure
    sudo unsquashfs -d filesystem "$squashfs_file"
    
    # Customize filesystem only
    customize_filesystem
    
    # Recreate ONLY the squashfs (preserve all boot files)
    log_info "Recreating squashfs without touching boot structure..."
    sudo rm "$squashfs_file"
    sudo mksquashfs filesystem "$squashfs_file" -comp xz -e boot
    
    # Add our autoinstall files
    add_autoinstall_config
    
    # Create ISO preserving EXACT boot structure
    create_exact_iso
}

customize_filesystem() {
    log_info "Customizing filesystem..."
    
    # Setup chroot
    sudo mkdir -p filesystem/{dev/pts,proc,sys}
    sudo mount --bind /dev filesystem/dev
    sudo mount --bind /proc filesystem/proc  
    sudo mount --bind /sys filesystem/sys
    sudo mount --bind /dev/pts filesystem/dev/pts
    sudo cp /etc/resolv.conf filesystem/etc/resolv.conf
    
    # Copy WiFi scripts with proper permissions
    sudo mkdir -p filesystem/opt/wifi-roam
    sudo cp "$SCRIPT_DIR/parameters.txt" filesystem/opt/wifi-roam/
    sudo cp "$SCRIPT_DIR/wifi_roam_setup.sh" filesystem/opt/wifi-roam/
    sudo cp "$SCRIPT_DIR/roam_script.sh" filesystem/opt/wifi-roam/
    sudo cp "$SCRIPT_DIR/speedtest_script.sh" filesystem/opt/wifi-roam/
    sudo cp "$SCRIPT_DIR/wpa_supplicant.conf" filesystem/opt/wifi-roam/
    
    # Make scripts executable
    sudo chmod +x filesystem/opt/wifi-roam/*.sh
    
    # Create log directory
    sudo mkdir -p filesystem/var/log/wifi-roam
    
    # Install packages
    sudo chroot filesystem apt-get update
    sudo chroot filesystem apt-get install -y openssh-server wpasupplicant dhcpcd5 iw wireless-tools speedtest-cli wget curl systemd
    
    # Create systemd service for first boot setup
    log_info "Creating wifi-roam-firstboot.service..."
    sudo tee filesystem/etc/systemd/system/wifi-roam-firstboot.service > /dev/null << 'EOF'
[Unit]
Description=WiFi Roaming First Boot Setup
After=multi-user.target
Before=graphical.target
DefaultDependencies=yes
Requires=multi-user.target

[Service]
Type=oneshot
User=root
ExecStart=/bin/bash -c 'cd /opt/wifi-roam && ./wifi_roam_setup.sh /opt/wifi-roam/parameters.txt'
RemainAfterExit=yes
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable the service in chroot
    sudo chroot filesystem systemctl enable wifi-roam-firstboot.service
    
    # Set proper ownership for wifi-roam directory (will be fixed by the setup script too)
    sudo chroot filesystem chown -R root:root /opt/wifi-roam
    sudo chroot filesystem chown -R root:root /var/log/wifi-roam
    
    # Cleanup chroot
    sudo umount filesystem/{dev/pts,dev,proc,sys} || true
}

add_autoinstall_config() {
    log_info "Adding autoinstall configuration..."
    cp "$SCRIPT_DIR/custom-iso/user-data" custom/
    cp "$SCRIPT_DIR/custom-iso/meta-data" custom/
    
    # Copy custom GRUB menu (critical for autoinstall)
    if [ -f "$SCRIPT_DIR/custom-iso/grub.cfg" ]; then
        cp "$SCRIPT_DIR/custom-iso/grub.cfg" custom/boot/grub/grub.cfg
        log_success "Custom GRUB menu installed"
    else
        log_error "Custom grub.cfg not found at $SCRIPT_DIR/custom-iso/grub.cfg"
        exit 1
    fi
}

create_exact_iso() {
    log_info "Creating ISO with EXACT original boot structure preserved..."
    
    cd custom/
    
    # Verify we preserved the exact boot structure
    log_info "Final boot structure check:"
    find . -name "*.img" | while read -r file; do
        log_info "  Boot file: $file"
    done
    
    # Use the SIMPLEST possible xorriso command to preserve everything
    log_info "Using minimal xorriso to preserve exact boot structure..."
    
    # Remove any existing ISO
    [ -f "$CUSTOM_ISO" ] && rm "$CUSTOM_ISO"
    
    # Create ISO for BOTH legacy and UEFI boot (hybrid)
    log_info "Creating hybrid ISO (legacy BIOS + UEFI)..."
    
    xorriso -as mkisofs \
        -V "Ubuntu-Server ${UBUNTU_VERSION} LTS amd64" \
        -r \
        -J -l \
        -b boot/grub/i386-pc/eltorito.img \
        -c boot.catalog \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e EFI/boot/bootx64.efi \
        -no-emul-boot \
        -o "$CUSTOM_ISO" \
        .
    
    if [ -f "$CUSTOM_ISO" ]; then
        log_success "EXACT STRUCTURE ISO created: $CUSTOM_ISO"
        log_info "ISO size: $(du -h "$CUSTOM_ISO" | cut -f1)"
        
        # Final verification
        log_info "Verifying final ISO boot structure..."
        mkdir -p ../verify
        sudo mount -o loop,ro "$CUSTOM_ISO" ../verify/ 2>/dev/null || true
        local final_boot_files=$(find ../verify -name "*.img" 2>/dev/null | wc -l)
        sudo umount ../verify/ 2>/dev/null || true
        rmdir ../verify 2>/dev/null || true
        
        log_info "Final ISO boot files: $final_boot_files"
        if [ "$final_boot_files" -eq 1 ]; then
            log_success "SUCCESS: Exact boot structure preserved (1 boot file)"
        else
            log_warning "Still have $final_boot_files boot files instead of 1"
        fi
    else
        log_error "Failed to create ISO"
        exit 1
    fi
}

main "$@"
