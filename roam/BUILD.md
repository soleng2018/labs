# WiFi Roaming Ubuntu Custom ISO Builder

## Quick Start

### 1. Configure WiFi Credentials
Edit `parameters.txt`:
```bash
SSID="YourWiFiNetwork"
USERNAME="your-username"  
PASSWORD="your-password"
```

### 2. Build Custom ISO
```bash
./build-custom-iso.sh
```

### 3. Use the ISO
The created ISO will be: `ubuntu-24.04.3-wifi-roaming-server-EXACT.iso`

**Login credentials:**
- Username: `wifiroam`
- Password: `wifiroam` 

## What it includes

- ✅ Fully automated Ubuntu Server 24.04.3 installation
- ✅ Pre-installed WiFi packages (wpasupplicant, dhcpcd5, iw, wireless-tools)  
- ✅ Embedded WiFi roaming scripts
- ✅ Automatic WiFi connection and speed testing after boot
- ✅ Legacy BIOS + UEFI boot support

## Testing in QEMU

### Legacy BIOS (recommended):
```bash
qemu-system-x86_64 -m 2G -enable-kvm \
  -boot d -cdrom ubuntu-24.04.3-wifi-roaming-server-EXACT.iso \
  -drive file=test.img,format=qcow2,size=10G,if=virtio
```

### UEFI:
```bash  
qemu-system-x86_64 -m 2G -enable-kvm \
  -boot d -cdrom ubuntu-24.04.3-wifi-roaming-server-EXACT.iso \
  -drive file=test.img,format=qcow2,size=10G,if=virtio \
  -bios /usr/share/ovmf/OVMF.fd
```

## Files

- `build-custom-iso.sh` - Main build script
- `parameters.txt` - WiFi configuration
- `custom-iso/user-data` - Ubuntu autoinstall config
- `*.sh` - WiFi roaming scripts
- `wpa_supplicant.conf` - WiFi template
