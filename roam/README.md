# Ubuntu WiFi Roaming Custom ISO Builder

Creates a fully automated Ubuntu Server ISO that installs and configures a WiFi roaming system with zero user intervention.

## 🚀 Quick Start

1. **Build the ISO:**
   ```bash
   cd path/to/roam
   sudo ./build-custom-iso.sh
   ```

2. **Flash to USB and boot target system**

3. **System will automatically:**
   - Install Ubuntu Server 24.04.3
   - Configure WiFi roaming with your credentials
   - Start roaming and speed testing services

**Default Login:** `wifiroam` / `wifiroam` (⚠️ change this!)

## ✨ Features

- **Zero User Input**: Fully automated installation
- **Offline Installation**: All packages pre-embedded in ISO  
- **WiFi Roaming**: Auto-switches between access points (BSSIDs) within same SSID
- **Speed Testing**: Periodic network performance monitoring
- **Enterprise WiFi**: EAP-PEAP MSCHAPv2 authentication support
- **Persistent Services**: Continues working after reboots
- **Portable Build**: Works from any directory

## 📋 Requirements

### Build System (Your Machine)
- Ubuntu/Debian Linux with sudo access
- 8GB+ free disk space  
- Internet connection
- Tools auto-installed: `xorriso`, `squashfs-tools`, `p7zip-full`, `genisoimage`

### Target System (Where ISO Installs)
- WiFi hardware compatible with Linux
- 2GB+ RAM, 10GB+ storage
- UEFI or Legacy BIOS support

## ⚙️ Configuration

Edit `parameters.txt` before building:

```bash
# WiFi Configuration
SSID="Alonso-ENT"           # Your WiFi network name
USERNAME="employee"          # Enterprise username  
PASSWORD="nilesecure"        # Enterprise password

# Roaming Behavior
MIN_TIME=10                  # Min minutes between roams
MAX_TIME=20                  # Max minutes between roams  
MIN_SIGNAL=-75               # Min signal strength (dBm)

# Speed Testing
SPEEDTEST_MIN_TIME=5         # Min minutes between speed tests
SPEEDTEST_MAX_TIME=10        # Max minutes between speed tests
```

## 🏗️ Build Process

The `build-custom-iso.sh` script:

1. **Prerequisites**: Auto-installs required tools
2. **Download**: Gets Ubuntu 24.04.3 Server ISO (~3GB)
3. **Extract**: Unpacks original ISO structure  
4. **Customize**: 
   - Installs WiFi packages offline: `wpasupplicant`, `dhcpcd5`, `iw`, `wireless-tools`, `speedtest-cli`
   - Embeds your WiFi scripts in `/opt/wifi-roam/`
   - Creates `wifi-roam-firstboot.service` for auto-setup
5. **Rebuild**: Creates custom bootable ISO

**Output:** `ubuntu-24.04.3-wifi-roaming-server-EXACT.iso`

## 💾 Installation Process

1. **Boot Menu**: Select "Install WiFi Roaming Ubuntu Server (Automated)"
2. **Auto Install**: Ubuntu installs with no user input required
3. **First Boot**: System automatically:
   - Configures WiFi authentication  
   - Sets up roaming services
   - Connects to WiFi and begins roaming
4. **Persistent**: Services restart automatically after reboots

## 🔧 Services Created

After installation, three systemd services run automatically:

### 1. wifi-startup.service
- **Purpose**: Initial WiFi connection on boot
- **Script**: `/usr/local/bin/wifi-startup.sh`

### 2. wifi-roaming.service  
- **Purpose**: Auto-roaming between access points
- **Script**: `/opt/wifi-roam/roam_script.sh`

### 3. wifi-speedtest.service
- **Purpose**: Periodic network speed testing
- **Script**: `/opt/wifi-roam/speedtest_script.sh`

## 📊 Monitoring

```bash
# Check service status
systemctl status wifi-roaming.service
systemctl status wifi-speedtest.service

# View real-time logs
journalctl -u wifi-roaming.service -f
journalctl -u wifi-speedtest.service -f

# WiFi status
sudo wpa_cli -i wlan0 status
ip addr show
```

## 🗂️ Project Structure

```
roam/
├── build-custom-iso.sh              # Main build script
├── parameters.txt                   # WiFi configuration
├── wifi_roam_setup.sh              # System setup script
├── roam_script.sh                  # WiFi roaming logic
├── speedtest_script.sh             # Speed testing script
├── wpa_supplicant.conf             # WiFi auth template
├── custom-iso/                     # Autoinstall configuration
│   ├── user-data                   # Installation config
│   ├── meta-data                   # Cloud-init metadata
│   └── grub.cfg                    # Boot menu config
└── README.md                       # This documentation
```

## 🧪 Testing

### VM Testing (No WiFi Hardware)
```bash
# Boot ISO in VM to verify installation process
qemu-system-x86_64 -cdrom ubuntu-24.04.3-wifi-roaming-server-EXACT.iso -m 2048
```

### Physical Hardware
1. Flash to USB: `sudo dd if=ubuntu-*.iso of=/dev/sdX bs=4M status=progress`
2. Boot target system from USB
3. Verify automated installation
4. Check WiFi connectivity and roaming

## 🛠️ Troubleshooting

### Build Issues
- **Missing tools**: Script auto-installs prerequisites
- **Download fails**: Check internet connection  
- **Space issues**: Need 8GB+ free space

### Runtime Issues
- **No WiFi**: Verify credentials in `parameters.txt`
- **No roaming**: Check multiple BSSIDs exist for SSID
- **Service failures**: Check logs with `journalctl -u service-name`

### Manual Testing
```bash
# Test roaming script
cd /opt/wifi-roam
sudo ./roam_script.sh --help

# Check WiFi interfaces  
ip link show
iw dev
```

## 🔒 Security Notes

⚠️ **Change Default Credentials**: Username `wifiroam`, Password `wifiroam`

⚠️ **WiFi Credentials**: Stored in plain text in parameters.txt

⚠️ **Certificate Validation**: Disabled by default (convenient but insecure)

## 🎛️ Customization

### Change Default User
Edit `custom-iso/user-data`:
```yaml
identity:
  username: youruser
  password: $6$encrypted$hash
  hostname: your-hostname
```

### Multiple WiFi Networks
Modify `wpa_supplicant.conf` template to add multiple network blocks.

### Additional Packages  
Add to `packages:` list in `custom-iso/user-data`.

## 🔄 Offline Installation Advantages

✅ **No Internet Required**: All packages pre-installed  
✅ **Fast Installation**: No download delays  
✅ **Robust**: Continues even if components fail  
✅ **Autonomous**: Zero user intervention needed

## 🏆 Success Checklist

- [ ] ISO boots with custom GRUB menu
- [ ] Installation completes automatically
- [ ] System reboots successfully  
- [ ] WiFi services start automatically
- [ ] WiFi connects without intervention
- [ ] Roaming works between access points
- [ ] Speed tests run periodically
- [ ] Services persist after reboot

---

**🎯 Your WiFi roaming system is ready to deploy!** The build process creates a fully autonomous Ubuntu installation that handles everything from WiFi authentication to automatic roaming between access points.
