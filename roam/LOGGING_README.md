# WiFi Roaming Logging System

This document describes the logging system for the WiFi roaming and speedtest functionality.

## Log Directory Structure

All logs are stored in `/var/log/wifi-roam/`:

```
/var/log/wifi-roam/
├── roaming.log          # Main roaming events
├── roaming-debug.log    # Detailed roaming debug information
├── speedtest.log        # Main speedtest events
└── speedtest-debug.log  # Detailed speedtest debug information
```

## Log Files Description

### Roaming Logs

- **`roaming.log`**: Contains major roaming events such as:
  - Script startup/shutdown
  - Successful roaming attempts
  - Roaming failures
  - BSSID discovery results
  - Connection status changes

- **`roaming-debug.log`**: Contains detailed debug information including:
  - Interface validation steps
  - Scan results and parsing
  - Signal strength measurements
  - WPA supplicant interactions
  - All INFO, WARNING, and ERROR messages

### Speedtest Logs

- **`speedtest.log`**: Contains major speedtest events such as:
  - Test start/completion
  - Download/upload speeds
  - Ping measurements
  - Test failures or skips

- **`speedtest-debug.log`**: Contains detailed debug information including:
  - Network connectivity checks
  - Speedtest-cli installation status
  - Interface detection
  - All INFO, WARNING, and ERROR messages

## Log Rotation

Log files are automatically rotated daily using logrotate:
- Keeps 7 days of logs
- Compresses old logs
- Maintains proper permissions (644 root:root)

## Viewing Logs

### Using the Log Viewer Script

A convenient script is provided at `/opt/wifi-roam/view_logs.sh`:

```bash
# Show all logs
/opt/wifi-roam/view_logs.sh

# Show only roaming events
/opt/wifi-roam/view_logs.sh roaming

# Follow speedtest log in real-time
/opt/wifi-roam/view_logs.sh -f speedtest

# Show last 100 lines of roaming debug log
/opt/wifi-roam/view_logs.sh -t 100 roaming-debug

# Show all content of speedtest log
/opt/wifi-roam/view_logs.sh -a speedtest
```

### Manual Log Viewing

You can also view logs directly:

```bash
# View roaming events
tail -f /var/log/wifi-roam/roaming.log

# View speedtest events
tail -f /var/log/wifi-roam/speedtest.log

# View all logs
tail -f /var/log/wifi-roam/*.log
```

## Log Format

All log entries follow this format:
```
[YYYY-MM-DD HH:MM:SS] [LEVEL] MESSAGE
```

Example:
```
[2024-01-15 14:30:25] [ROAM_EVENT] ROAM_SUCCESS: Successfully roamed from aa:bb:cc:dd:ee:ff to 11:22:33:44:55:66
[2024-01-15 14:35:10] [SPEEDTEST_EVENT] TEST_COMPLETE: Interface wlan0 - Download: 45.2 Mbit/s, Upload: 12.8 Mbit/s, Ping: 15 ms
```

## Log Levels

- **INFO**: General information messages
- **SUCCESS**: Successful operations
- **WARNING**: Warning messages (non-critical issues)
- **ERROR**: Error messages (critical issues)
- **ROAM_EVENT**: Major roaming events
- **SPEEDTEST_EVENT**: Major speedtest events

## Systemd Services

The logging system is integrated with systemd services:

- **`wifi-roaming.service`**: Runs the roaming script
- **`wifi-speedtest.service`**: Runs the speedtest script
- **`wifi-roam-firstboot.service`**: Initial setup service

View service logs with:
```bash
# View roaming service logs
journalctl -u wifi-roaming.service -f

# View speedtest service logs
journalctl -u wifi-speedtest.service -f

# View firstboot service logs
journalctl -u wifi-roam-firstboot.service -f
```

## Troubleshooting

### No Logs Appearing

1. Check if services are running:
   ```bash
   systemctl status wifi-roaming.service
   systemctl status wifi-speedtest.service
   ```

2. Check service logs:
   ```bash
   journalctl -u wifi-roaming.service
   journalctl -u wifi-speedtest.service
   ```

3. Verify log directory permissions:
   ```bash
   ls -la /var/log/wifi-roam/
   ```

### Log Files Not Created

1. Ensure the firstboot service completed successfully
2. Check if the log directory exists and has proper permissions
3. Verify the scripts can write to the log directory

### High Log Volume

If logs are growing too large:
1. Check logrotate configuration: `/etc/logrotate.d/wifi-roam`
2. Adjust rotation settings if needed
3. Consider increasing the rotation count or compression

## Monitoring

For production monitoring, consider:
- Setting up log aggregation (ELK stack, Splunk, etc.)
- Configuring alerts for ERROR level messages
- Monitoring log file sizes and rotation
- Setting up dashboards for roaming and speedtest metrics

