FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install required packages for WiFi management and networking
RUN apt-get update && apt-get install -y \
    wireless-tools \
    wpasupplicant \
    iw \
    net-tools \
    iproute2 \
    iputils-ping \
    usbutils \
    pciutils \
    dbus \
    systemd \
    nano \
    curl \
    wget \
    sudo \
    cron \
    rsyslog \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /var/run/wpa_supplicant \
    /etc/wpa_supplicant \
    /var/log/wpa_supplicant \
    /app/scripts \
    /app/config

# Create a non-root user with sudo privileges
RUN useradd -m -s /bin/bash roamuser && \
    echo "roamuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/roamuser

# Copy application scripts
COPY scripts/ /app/scripts/
COPY config/ /app/config/

# Make scripts executable
RUN chmod +x /app/scripts/*.sh

# Set up dbus for wpa_supplicant
RUN mkdir -p /var/run/dbus

# Create wpa_supplicant control interface directory
RUN mkdir -p /var/run/wpa_supplicant && \
    chown -R roamuser:roamuser /var/run/wpa_supplicant

# Set working directory
WORKDIR /app

# Switch to non-root user
USER roamuser

# Default command
CMD ["/app/scripts/entrypoint.sh"]
