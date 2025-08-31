# Custom Ubuntu ISO with WiFi Roaming System

This project creates a custom Ubuntu Server ISO that automatically installs and configures a WiFi roaming system with no user intervention required.

## Features

- **Fully Automated Installation**: No user interaction required during installation
- **Offline Package Installation**: All required packages are pre-installed in the ISO
- **WiFi Roaming**: Automatically switches between WiFi access points (BSSIDs) within the same SSID
- **Speed Testing**: Periodic network speed tests with configurable intervals
- **Persistent Configuration**: Services restart automatically after system reboots
- **Enterprise WiFi Support**: Pre-configured for EAP-PEAP MSCHAPv2 authentication

## Prerequisites

### Build System Requirements

- Ubuntu 20.04+ or Debian-based Linux system
- Root/sudo access
- At least 8GB free disk space
- Internet connection (for downloading base Ubuntu ISO and packages)

### Required Tools (auto-installed by build script)
- `xorriso` - ISO creation tool
- `p7zip-full` - Archive extraction
- `squashfs-tools` - Filesystem manipulation
- `genisoimage` - ISO image creation
- `wget` - File downloading

### Target System Requirements
- WiFi hardware compatible with Linux
- UEFI or Legacy BIOS boot support
- At least 2GB RAM
- At least 10GB storage space

## Quick Start

1. **Clone and navigate to the project directory**
```bash
cd /path/to/your/roam/directory
```

2. **Build the custom ISO**
```bash
sudo ./build-custom-iso.sh
```

3. **Burn to USB drive**
```bash
sudo dd if=ubuntu-24.04.3-wifi-roaming-server.iso of=/dev/sdX bs=4M status=progress
sync
```

4. **Boot target system from USB and select automated installation**

## Configuration

### WiFi Network Settings

Edit `parameters.txt` before building the ISO:

```bash
# WiFi Configuration Parameters
SSID="Alonso-ENT"           # Your WiFi network name
USERNAME="employee"          # Your enterprise username
PASSWORD="nilesecure"        # Your enterprise password

# Roaming Configuration
MIN_TIME=10                  # Minimum minutes between roams
MAX_TIME=20                  # Maximum minutes between roams
MIN_SIGNAL=-75               # Minimum signal strength (dBm)

# Speedtest Configuration  
SPEEDTEST_MIN_TIME=5         # Minimum minutes between speed tests
SPEEDTEST_MAX_TIME=10        # Maximum minutes between speed tests

# Interface (leave empty for auto-detection)
INTERFACE=""
```

### System User Configuration

Default user created during installation:
- Username: `wifiroam`
- Password: `wifiroam` (change via user-data if needed)
- Hostname: `wifi-roaming-system`

## File Structure

```
roam/
├── build-custom-iso.sh           # Main build script
├── custom-iso/
│   ├── user-data                 # Autoinstall configuration
│   ├── meta-data                 # Cloud-init metadata
│   ├── grub.cfg                  # GRUB boot menu
│   └── wifi-roam/                # WiFi roaming scripts
│       ├── parameters.txt        # WiFi configuration
│       ├── roam_script.sh        # Main roaming logic
│       ├── speedtest_script.sh   # Speed testing
│       ├── wifi_roam_setup.sh    # System setup script
│       └── wpa_supplicant.conf   # WiFi template config
├── roam_script.sh                # Source roaming script
├── speedtest_script.sh           # Source speed test script
├── wifi_roam_setup.sh            # Source setup script (modified)
├── wpa_supplicant.conf           # Source WiFi template
├── parameters.txt                # Source configuration
└── README-CUSTOM-ISO.md          # This documentation
```

## Build Process Details

The `build-custom-iso.sh` script performs the following steps:

1. **Prerequisites Check**: Installs required tools if missing
2. **Download Ubuntu ISO**: Downloads Ubuntu 24.04.3 Server ISO
3. **Extract ISO**: Extracts the original ISO contents
4. **Customize Filesystem**: 
   - Mounts the squashfs filesystem
   - Installs WiFi packages: `wpasupplicant`, `dhcpcd5`, `iw`, `wireless-tools`, `speedtest-cli`
   - Copies WiFi roaming scripts to `/opt/wifi-roam/`
   - Creates systemd service for first-boot setup
   - Rebuilds the filesystem
5. **Add Autoinstall**: Copies cloud-init configuration for automated installation
6. **Update GRUB**: Configures boot menu with automated option
7. **Create ISO**: Builds the final custom ISO file

## Installation Process

When booting from the custom ISO:

1. **Boot Menu**: Select "Install WiFi Roaming Ubuntu Server (Automated)"
2. **Automated Installation**: Ubuntu installs without user intervention
3. **First Boot Setup**: System automatically:
   - Configures WiFi authentication
   - Sets up roaming services
   - Starts WiFi connection
   - Begins roaming and speed testing
4. **Persistent Operation**: Services continue running after reboots

## Services Created

The system creates three systemd services:

### 1. wifi-startup.service
- **Purpose**: Initial WiFi connection on boot
- **Location**: `/etc/systemd/system/wifi-startup.service`
- **Script**: `/usr/local/bin/wifi-startup.sh`

### 2. wifi-roaming.service  
- **Purpose**: Automatic WiFi roaming between access points
- **Location**: `/etc/systemd/system/wifi-roaming.service` 
- **Script**: `/opt/wifi-roam/roam_script.sh`

### 3. wifi-speedtest.service
- **Purpose**: Periodic network speed testing
- **Location**: `/etc/systemd/system/wifi-speedtest.service`
- **Script**: `/opt/wifi-roam/speedtest_script.sh`

## Monitoring and Troubleshooting

### Check Service Status
```bash
# Check all WiFi services
systemctl status wifi-startup.service
systemctl status wifi-roaming.service  
systemctl status wifi-speedtest.service
```

### View Service Logs
```bash
# Follow logs in real-time
journalctl -u wifi-startup.service -f
journalctl -u wifi-roaming.service -f
journalctl -u wifi-speedtest.service -f

# View recent logs
journalctl -u wifi-roaming.service --since "1 hour ago"
```

### Manual Testing
```bash
# Test WiFi connectivity
sudo wpa_cli -i wlan0 status
sudo wpa_cli -i wlan0 scan_results

# Test roaming script manually
cd /opt/wifi-roam
sudo ./roam_script.sh --help

# Test speed test
sudo ./speedtest_script.sh --help
```

### Network Interface Status
```bash
# Check wireless interfaces
ip link show
iw dev
iwconfig

# Check IP addresses
ip addr show
```

## Offline Installation Handling

The modified scripts handle offline installation gracefully:

### Package Installation (`wifi_roam_setup.sh`)
- Checks if packages are already installed before attempting installation
- Continues setup even if `apt-get` fails
- Provides detailed logging about missing packages

### Speed Test (`speedtest_script.sh`)
- Creates dummy speedtest-cli if installation fails
- Returns placeholder values instead of crashing
- Continues monitoring even without real speedtest capability

## Customization Options

### Change WiFi Credentials
Edit `custom-iso/wifi-roam/parameters.txt` before building the ISO.

### Modify Roaming Behavior
Adjust parameters in `parameters.txt`:
- `MIN_TIME`/`MAX_TIME`: Roaming frequency
- `MIN_SIGNAL`: Signal strength threshold

### Change Default User
Edit `custom-iso/user-data` and modify the identity section:
```yaml
identity:
  realname: Your Name
  username: yourusername
  password: $6$encrypted$password$hash
  hostname: your-hostname
```

### Add Additional Packages
Edit `custom-iso/user-data` and add packages to the packages list:
```yaml
packages:
  - wpasupplicant
  - dhcpcd5
  # Add your packages here
  - your-package-name
```

## Testing the Custom ISO

### Virtual Machine Testing
1. Create VM with at least 2GB RAM and 20GB disk
2. Enable UEFI boot if available
3. Attach the custom ISO
4. Boot and verify automated installation
5. Check that services are created (they won't function without WiFi hardware)

### Physical Hardware Testing
1. Boot from USB on target hardware with WiFi
2. Verify automated installation completes
3. Check network connectivity after reboot
4. Monitor service logs for roaming activity

### Validation Checklist
- [ ] ISO boots and shows custom GRUB menu
- [ ] Automated installation completes without user input
- [ ] System reboots successfully  
- [ ] WiFi services are enabled and running
- [ ] WiFi connection establishes automatically
- [ ] Roaming functionality works between access points
- [ ] Speed tests execute periodically
- [ ] Services persist after system reboot

## Troubleshooting Common Issues

### Build Issues
- **Missing tools**: Run script as root to auto-install prerequisites  
- **Download fails**: Check internet connection and try again
- **Insufficient space**: Ensure at least 8GB free disk space

### Installation Issues
- **Boot fails**: Verify UEFI/BIOS compatibility and USB burn integrity
- **Installation hangs**: Check that automation config is properly embedded

### Runtime Issues
- **WiFi not connecting**: Verify credentials in parameters.txt
- **No roaming**: Check that multiple BSSIDs exist for the SSID
- **Service failures**: Check logs with journalctl

## Advanced Configuration

### Multiple WiFi Networks
To support multiple networks, modify `wpa_supplicant.conf` template to include multiple network blocks.

### Custom Certificate Validation
For enterprise networks requiring certificate validation, modify the wpa_supplicant.conf template and provide certificate files.

### Additional First-Boot Tasks
Add commands to the `late-commands` section in `user-data` for additional system configuration.

## Security Considerations

- Default user password is public - change it immediately
- WiFi credentials are stored in plain text in parameters.txt
- Certificate validation is disabled by default (insecure)
- SSH is enabled by default for remote access

## Support and Maintenance

### Updating the Base Ubuntu Version
1. Edit `UBUNTU_VERSION` in `build-custom-iso.sh`
2. Update the download URL accordingly
3. Test compatibility with newer Ubuntu versions

### Script Updates  
The roaming and speedtest scripts can be updated independently by modifying the files in `custom-iso/wifi-roam/` before building.

### Package Updates
To include newer package versions, the build script will automatically download the latest available versions during the build process.
