#!/bin/bash

# Alternative Ubuntu 24.04.3 Custom ISO Builder with UEFI Focus
# This script uses genisoimage and a different approach for UEFI boot

set -e

# Configuration
UBUNTU_VERSION="24.04.3"
UBUNTU_ISO_NAME="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
UBUNTU_ISO_URL="https://releases.ubuntu.com/24.04/${UBUNTU_ISO_NAME}"
WORK_DIR="/home/nile/labs/roam/iso-build-alt"
ISO_EXTRACT_DIR="$WORK_DIR/iso-extract"
ISO_NEW_DIR="$WORK_DIR/iso-new"
FILESYSTEM_DIR="$WORK_DIR/filesystem"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    sudo umount "$FILESYSTEM_DIR/dev/pts" 2>/dev/null || true
    sudo umount "$FILESYSTEM_DIR/dev" 2>/dev/null || true
    sudo umount "$FILESYSTEM_DIR/proc" 2>/dev/null || true
    sudo umount "$FILESYSTEM_DIR/sys" 2>/dev/null || true
    sudo umount /tmp/efi_mount 2>/dev/null || true
    sudo rmdir /tmp/efi_mount 2>/dev/null || true
}

trap cleanup EXIT

main() {
    log_info "Starting Alternative Ubuntu 24.04.3 ISO build with UEFI focus..."
    
    # Create work directories
    mkdir -p "$WORK_DIR" "$ISO_EXTRACT_DIR" "$ISO_NEW_DIR" "$FILESYSTEM_DIR"
    cd "$WORK_DIR"
    
    # Download original ISO if needed
    if [ ! -f "$UBUNTU_ISO_NAME" ]; then
        log_info "Downloading Ubuntu 24.04.3 ISO..."
        wget -O "$UBUNTU_ISO_NAME" "$UBUNTU_ISO_URL"
    fi
    
    # Extract original ISO using different method
    log_info "Extracting original ISO using osirrox..."
    rm -rf "$ISO_EXTRACT_DIR"
    mkdir -p "$ISO_EXTRACT_DIR"
    
    # Use xorriso in extraction mode (more reliable than 7z)
    cd "$ISO_EXTRACT_DIR"
    xorriso -osirrox on -indev "../$UBUNTU_ISO_NAME" -extract / .
    
    # Copy to working directory
    log_info "Setting up ISO working directory..."
    rm -rf "$ISO_NEW_DIR"
    cp -r "$ISO_EXTRACT_DIR" "$ISO_NEW_DIR"
    cd "$ISO_NEW_DIR"
    
    # Find and extract the correct squashfs
    log_info "Finding squashfs filesystem..."
    local squashfs_file=""
    for file in casper/*.squashfs; do
        if [[ "$file" == *"filesystem.squashfs"* ]] || [[ "$file" == *"ubuntu-server-minimal.squashfs"* ]]; then
            squashfs_file="$file"
            break
        fi
    done
    
    if [ -z "$squashfs_file" ]; then
        # Take the first squashfs file
        squashfs_file=$(find casper -name "*.squashfs" | head -1)
    fi
    
    if [ -z "$squashfs_file" ]; then
        log_error "No squashfs file found!"
        exit 1
    fi
    
    log_info "Using squashfs: $squashfs_file"
    
    # Extract filesystem
    log_info "Extracting filesystem..."
    rm -rf "$FILESYSTEM_DIR"
    sudo unsquashfs -d "$FILESYSTEM_DIR" "$squashfs_file"
    
    # Set up chroot environment
    log_info "Setting up chroot environment..."
    setup_chroot
    
    # Install packages and configure system
    log_info "Customizing filesystem..."
    customize_filesystem
    
    # Create new squashfs
    log_info "Creating new squashfs..."
    rm -f "$squashfs_file"
    sudo mksquashfs "$FILESYSTEM_DIR" "$squashfs_file" -comp xz -e boot
    
    # Add autoinstall configuration
    log_info "Adding autoinstall configuration..."
    add_autoinstall_config
    
    # Create EFI boot image properly
    log_info "Creating proper EFI boot configuration..."
    create_efi_boot_image
    
    # Create ISO using genisoimage (alternative to xorriso)
    log_info "Creating ISO using genisoimage approach..."
    create_iso_genisoimage
    
    log_success "Alternative ISO build completed!"
}

setup_chroot() {
    sudo mkdir -p "$FILESYSTEM_DIR"/{dev,proc,sys,dev/pts}
    sudo mount --bind /dev "$FILESYSTEM_DIR/dev"
    sudo mount --bind /proc "$FILESYSTEM_DIR/proc"
    sudo mount --bind /sys "$FILESYSTEM_DIR/sys"
    sudo mount --bind /dev/pts "$FILESYSTEM_DIR/dev/pts"
    sudo cp /etc/resolv.conf "$FILESYSTEM_DIR/etc/resolv.conf"
}

customize_filesystem() {
    # Copy WiFi scripts
    log_info "Copying WiFi roaming scripts..."
    sudo mkdir -p "$FILESYSTEM_DIR/opt/wifi-roaming"
    sudo cp ../../parameters.txt "$FILESYSTEM_DIR/opt/wifi-roaming/"
    sudo cp ../../*.sh "$FILESYSTEM_DIR/opt/wifi-roaming/"
    sudo cp ../../wpa_supplicant.conf "$FILESYSTEM_DIR/opt/wifi-roaming/"
    
    # Install packages
    log_info "Installing required packages..."
    sudo chroot "$FILESYSTEM_DIR" apt-get update
    sudo chroot "$FILESYSTEM_DIR" apt-get install -y wpasupplicant dhcpcd5 iw wireless-tools speedtest-cli wget curl systemd
    
    # Create service
    sudo tee "$FILESYSTEM_DIR/etc/systemd/system/wifi-roam-firstboot.service" > /dev/null << 'EOF'
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
    
    sudo chroot "$FILESYSTEM_DIR" systemctl enable wifi-roam-firstboot.service
    
    # Cleanup chroot
    sudo umount "$FILESYSTEM_DIR/dev/pts" || true
    sudo umount "$FILESYSTEM_DIR/dev" || true
    sudo umount "$FILESYSTEM_DIR/proc" || true
    sudo umount "$FILESYSTEM_DIR/sys" || true
}

add_autoinstall_config() {
    # Copy autoinstall files
    cp ../../custom-iso/user-data .
    cp ../../custom-iso/meta-data .
}

create_efi_boot_image() {
    log_info "Creating proper EFI System Partition..."
    
    # Extract the original EFI boot image if it exists
    local efi_img=""
    if [ -f "boot/grub/efi.img" ]; then
        efi_img="boot/grub/efi.img"
    elif find . -name "*.img" | grep -q efi; then
        efi_img=$(find . -name "*.img" | grep efi | head -1)
    fi
    
    if [ -n "$efi_img" ]; then
        log_info "Found existing EFI image: $efi_img"
        # Modify the existing EFI image to include our custom GRUB config
        mkdir -p /tmp/efi_mount
        sudo mount -o loop "$efi_img" /tmp/efi_mount 2>/dev/null || true
        
        # Update GRUB configuration in EFI image
        if [ -d "/tmp/efi_mount/EFI/ubuntu" ]; then
            sudo cp ../../custom-iso/grub.cfg /tmp/efi_mount/EFI/ubuntu/grub.cfg 2>/dev/null || true
        fi
        
        sudo umount /tmp/efi_mount 2>/dev/null || true
        rmdir /tmp/efi_mount
    fi
}

create_iso_genisoimage() {
    local output_iso="/home/nile/labs/roam/ubuntu-24.04.3-wifi-roaming-server-alt.iso"
    
    # Method 1: Use genisoimage with UEFI support
    if command -v genisoimage >/dev/null 2>&1; then
        log_info "Creating ISO with genisoimage..."
        
        # Find EFI boot file
        local efi_boot=""
        if [ -f "boot/grub/efi.img" ]; then
            efi_boot="boot/grub/efi.img"
        elif [ -f "EFI/boot/bootx64.efi" ]; then
            efi_boot="EFI/boot/bootx64.efi"  
        fi
        
        if [ -n "$efi_boot" ]; then
            log_info "Using EFI boot: $efi_boot"
            genisoimage -r -V "WiFi-Roaming-Ubuntu-24.04.3" \
                -cache-inodes -J -l \
                -eltorito-alt-boot \
                -e "$efi_boot" \
                -no-emul-boot \
                -o "$output_iso" \
                .
        else
            log_error "No EFI boot file found for genisoimage"
            return 1
        fi
    else
        log_info "genisoimage not available, using enhanced xorriso..."
        
        # Method 2: Enhanced xorriso with different parameters
        local efi_boot="EFI/boot/bootx64.efi"
        if [ -f "$efi_boot" ]; then
            # Try creating a hybrid boot ISO with specific UEFI parameters
            xorriso -as mkisofs \
                -r -V "WiFi-Roaming-Ubuntu-24.04.3" \
                -J -joliet-long \
                -c boot.catalog \
                -eltorito-alt-boot \
                -e "$efi_boot" \
                -no-emul-boot \
                -boot-load-size 1 \
                -isohybrid-gpt-basdat \
                -o "$output_iso" \
                .
        else
            log_error "No EFI boot file found!"
            return 1
        fi
    fi
    
    if [ -f "$output_iso" ]; then
        log_success "Alternative ISO created: $output_iso"
        log_info "ISO size: $(du -h "$output_iso" | cut -f1)"
        
        # Show file information
        log_info "ISO file structure:"
        file "$output_iso"
        
        # Show partition table if present
        log_info "ISO partition structure:"
        fdisk -l "$output_iso" 2>/dev/null || log_info "No partition table found"
    else
        log_error "Failed to create ISO!"
        return 1
    fi
}

# Run main function
main "$@"
