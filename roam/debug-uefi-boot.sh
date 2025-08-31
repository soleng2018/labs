#!/bin/bash

echo "=== UEFI Boot Debug Analysis ==="
echo "Please run this script on the nile system to analyze the boot structure."
echo ""

# Set paths
ORIGINAL_ISO="/home/nile/labs/roam/iso-build/ubuntu-24.04.3-live-server-amd64.iso"
CUSTOM_ISO="/home/nile/labs/roam/ubuntu-24.04.3-wifi-roaming-server.iso"
WORK_DIR="/home/nile/labs/roam/iso-build"

echo "1. Analyzing Original Ubuntu ISO boot structure..."
if [ -f "$ORIGINAL_ISO" ]; then
    echo "   Original ISO file structure:"
    file "$ORIGINAL_ISO"
    echo ""
    
    echo "   Original ISO partition table:"
    fdisk -l "$ORIGINAL_ISO" 2>/dev/null || echo "   No partition table found"
    echo ""
    
    # Mount and examine original ISO
    mkdir -p /tmp/orig_iso_mount
    if sudo mount -o loop,ro "$ORIGINAL_ISO" /tmp/orig_iso_mount 2>/dev/null; then
        echo "   EFI boot files in original ISO:"
        find /tmp/orig_iso_mount -name "*.efi" -o -name "*.img" | sort
        echo ""
        
        echo "   GRUB configuration in original:"
        find /tmp/orig_iso_mount -name "grub.cfg" | head -3
        echo ""
        
        echo "   Boot directory structure:"
        ls -la /tmp/orig_iso_mount/boot/ 2>/dev/null || echo "   No /boot directory"
        echo ""
        
        echo "   EFI directory structure:"
        find /tmp/orig_iso_mount/EFI -type f 2>/dev/null | head -10 || echo "   No /EFI directory"
        
        sudo umount /tmp/orig_iso_mount 2>/dev/null
    else
        echo "   Could not mount original ISO"
    fi
    rmdir /tmp/orig_iso_mount 2>/dev/null
else
    echo "   Original ISO not found at $ORIGINAL_ISO"
fi

echo ""
echo "2. Analyzing Custom ISO boot structure..."
if [ -f "$CUSTOM_ISO" ]; then
    echo "   Custom ISO file structure:"
    file "$CUSTOM_ISO"
    echo ""
    
    echo "   Custom ISO partition table:"
    fdisk -l "$CUSTOM_ISO" 2>/dev/null || echo "   No partition table found"
    echo ""
    
    # Mount and examine custom ISO
    mkdir -p /tmp/custom_iso_mount
    if sudo mount -o loop,ro "$CUSTOM_ISO" /tmp/custom_iso_mount 2>/dev/null; then
        echo "   EFI boot files in custom ISO:"
        find /tmp/custom_iso_mount -name "*.efi" -o -name "*.img" | sort
        echo ""
        
        echo "   GRUB configuration in custom:"
        find /tmp/custom_iso_mount -name "grub.cfg" | head -3
        echo ""
        
        echo "   Boot directory structure:"
        ls -la /tmp/custom_iso_mount/boot/ 2>/dev/null || echo "   No /boot directory"
        echo ""
        
        echo "   EFI directory structure:"
        find /tmp/custom_iso_mount/EFI -type f 2>/dev/null | head -10 || echo "   No /EFI directory"
        
        sudo umount /tmp/custom_iso_mount 2>/dev/null
    else
        echo "   Could not mount custom ISO"
    fi
    rmdir /tmp/custom_iso_mount 2>/dev/null
else
    echo "   Custom ISO not found at $CUSTOM_ISO"
fi

echo ""
echo "3. Comparing the difference..."
echo "   Please compare the EFI boot files and GRUB configurations above."
echo "   Look for missing files or structural differences."

echo ""
echo "4. Alternative approach - Extract working EFI from original:"
echo "   If the structures are different, we may need to:"
echo "   a) Extract the working EFI system partition from original ISO"
echo "   b) Create our own EFI boot image"
echo "   c) Use a different xorriso approach entirely"

echo ""
echo "=== Debug Complete ==="
