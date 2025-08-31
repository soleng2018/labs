# Ubuntu WiFi Roaming Custom ISO Builder

## Quick Start

The build script is now completely portable and works from any location.

### Prerequisites

- Ubuntu/Debian system with `sudo` access
- Required tools will be automatically installed by the script

### Build Process

1. **Navigate to the script directory:**
   ```bash
   cd /path/to/your/roam/directory
   ```

2. **Run the build script:**
   ```bash
   ./build-custom-iso.sh
   ```

The script will:
- Automatically detect its location and use relative paths
- Verify all required WiFi roaming files exist
- Download Ubuntu 24.04.3 server ISO if needed
- Create a custom bootable ISO with embedded WiFi roaming capabilities
- Output: `ubuntu-24.04.3-wifi-roaming-server-EXACT.iso`

### Required Files Structure

The script expects this directory structure:
```
roam/
├── build-custom-iso.sh           # Main build script
├── parameters.txt                # WiFi configuration
├── wpa_supplicant.conf          # WPA supplicant template
├── roam_script.sh               # Main roaming logic
├── speedtest_script.sh          # Speed testing
├── wifi_roam_setup.sh           # Setup script
└── custom-iso/                  # Autoinstall configuration
    ├── user-data
    ├── meta-data
    └── grub.cfg
```

### Installation Credentials

After installing the custom ISO:
- **Username:** `wifiroam`
- **Password:** `wifiroam`

The WiFi roaming system will start automatically on first boot via systemd service.

### Boot Modes

The generated ISO supports:
- **Legacy BIOS boot** (recommended for compatibility)
- **UEFI boot** (hybrid support)

For QEMU testing, use legacy boot for best results.