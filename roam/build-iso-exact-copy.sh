#!/bin/bash

# DEFINITIVE Ubuntu 24.04.3 Custom ISO Builder
# This approach preserves the EXACT boot structure from original Ubuntu ISO

set -e

# Configuration
UBUNTU_VERSION="24.04.3"
UBUNTU_ISO_NAME="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
UBUNTU_ISO_URL="https://releases.ubuntu.com/24.04/${UBUNTU_ISO_NAME}"
WORK_DIR="/home/nile/labs/roam/iso-exact"
ORIGINAL_ISO="/home/nile/labs/roam/iso-build/$UBUNTU_ISO_NAME"
CUSTOM_ISO="/home/nile/labs/roam/ubuntu-${UBUNTU_VERSION}-wifi-roaming-server-EXACT.iso"

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

cleanup() {
    sudo umount "$WORK_DIR/original" 2>/dev/null || true
    sudo umount "$WORK_DIR/custom" 2>/dev/null || true
    sudo umount "$WORK_DIR/filesystem"/{dev/pts,dev,proc,sys} 2>/dev/null || true
    sudo rm -rf "$WORK_DIR/original" "$WORK_DIR/custom" 2>/dev/null || true
}

trap cleanup EXIT

main() {
    log_info "Starting EXACT boot structure copy approach for Ubuntu 24.04.3"
    
    # Verify original ISO exists
    if [ ! -f "$ORIGINAL_ISO" ]; then
        log_error "Original Ubuntu ISO not found: $ORIGINAL_ISO"
        log_error "Please run the regular build script first to download it."
        exit 1
    fi
    
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
    
    # Copy WiFi scripts
    sudo mkdir -p filesystem/opt/wifi-roaming
    sudo cp /home/nile/labs/roam/parameters.txt filesystem/opt/wifi-roaming/
    sudo cp /home/nile/labs/roam/*.sh filesystem/opt/wifi-roaming/
    sudo cp /home/nile/labs/roam/wpa_supplicant.conf filesystem/opt/wifi-roaming/
    
    # Install packages
    sudo chroot filesystem apt-get update
    sudo chroot filesystem apt-get install -y wpasupplicant dhcpcd5 iw wireless-tools speedtest-cli wget curl systemd
    
    # Create service
    sudo tee filesystem/etc/systemd/system/wifi-roam-firstboot.service > /dev/null << 'EOF'
[Unit]
Description=WiFi Roaming First Boot Setup
After=network.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/opt/wifi-roaming/wifi_roam_setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    sudo chroot filesystem systemctl enable wifi-roam-firstboot.service
    
    # Cleanup chroot
    sudo umount filesystem/{dev/pts,dev,proc,sys} || true
}

add_autoinstall_config() {
    log_info "Adding autoinstall configuration..."
    cp /home/nile/labs/roam/custom-iso/user-data custom/
    cp /home/nile/labs/roam/custom-iso/meta-data custom/
    cp /home/nile/labs/roam/custom-iso/grub.cfg custom/boot/grub/ 2>/dev/null || true
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
