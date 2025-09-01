#!/bin/bash

# PXE Server Startup Script
# This script starts all required services for the PXE server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to start a service
start_service() {
    local service_name=$1
    log_info "Starting $service_name..."
    
    # In Docker container, we need to start services manually
    case $service_name in
        chronyd)
            if [ -f /usr/sbin/chronyd ]; then
                /usr/sbin/chronyd -d &
                log_info "chronyd started in background"
            fi
            ;;
        firewalld)
            if [ -f /usr/sbin/firewalld ]; then
                /usr/sbin/firewalld --nofork --nopid &
                log_info "firewalld started in background"
            fi
            ;;
        dhcpd)
            if [ -f /usr/sbin/dhcpd ]; then
                # Kill existing dhcpd process if running
                pkill -f dhcpd 2>/dev/null || true
                # Remove PID file if it exists
                rm -f /var/run/dhcpd.pid
                sleep 2
                /usr/sbin/dhcpd -f -d &
                log_info "dhcpd started in background"
            fi
            ;;
        tftp)
            if [ -f /usr/sbin/in.tftpd ]; then
                # Kill existing tftp process if running
                pkill -f tftpd 2>/dev/null || true
                # Remove PID file if it exists
                rm -f /var/run/in.tftpd.pid
                sleep 2
                # Start TFTP in foreground mode but redirect output and use setsid for proper daemonization
                setsid /usr/sbin/in.tftpd -s /var/lib/tftpboot -l -a 0.0.0.0:69 > /dev/null 2>&1 &
                TFTP_PID=$!
                # Create PID file manually
                echo $TFTP_PID > /var/run/in.tftpd.pid
                log_info "tftp started in background (PID: $TFTP_PID)"
            fi
            ;;
        *)
            log_warn "Service $service_name not configured for Docker"
            ;;
    esac
}

# Function to enable a service (no-op in Docker)
enable_service() {
    local service_name=$1
    log_info "Service $service_name will be started manually in Docker"
}

# Function to configure DHCP
configure_dhcp() {
    log_info "Configuring DHCP server..."
    
    # Create DHCP configuration with iPXE support
    cat > /etc/dhcp/dhcpd.conf << 'EOF'
# DHCP Server Configuration for PXE
default-lease-time 600;
max-lease-time 7200;
authoritative;

# PXE Boot Configuration - must be defined globally
option space pxelinux;
option pxelinux.magic code 208 = string;
option pxelinux.reboot-time code 209 = unsigned integer 32;
option pxelinux.menu code 16 = text;

# PXE Network Configuration
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    option domain-name-servers 192.168.1.2;
    option broadcast-address 192.168.1.255;
    
    # iPXE Configuration - detect iPXE clients more reliably
    if exists user-class and option user-class = "iPXE" {
        filename "menu.ipxe";
        next-server 192.168.1.2;
    } elsif option vendor-class-identifier = "PXEClient:Arch:00000:UNDI:002001" {
        # Traditional PXE clients get pxelinux.0
        filename "pxelinux.0";
        next-server 192.168.1.2;
    } else {
        # Default to iPXE for modern clients
        filename "menu.ipxe";
        next-server 192.168.1.2;
    }
    
    # Additional PXE options
    option tftp-server-name "192.168.1.2";
    option bootfile-name "pxelinux.0";
    
    # Allow booting
    allow booting;
    allow bootp;
}
EOF
    
    log_info "DHCP configuration created with iPXE support"
}

# Function to setup TFTP directory
setup_tftp() {
    log_info "Setting up TFTP directory..."
    
    # Ensure TFTP directory exists with proper permissions
    mkdir -p /var/lib/tftpboot
    chmod 755 /var/lib/tftpboot
    chown root:root /var/lib/tftpboot
    
    # Create basic PXE structure
    mkdir -p /var/lib/tftpboot/pxelinux.cfg
    chmod 755 /var/lib/tftpboot/pxelinux.cfg
    
    log_info "TFTP directory setup complete"
}

# Function to check if a service is running
check_service() {
    local service_name=$1
    local pid_file=""
    
    case $service_name in
        dhcpd)
            pid_file="/var/run/dhcpd.pid"
            ;;
        tftp)
            pid_file="/var/run/in.tftpd.pid"
            ;;
        *)
            return 1
            ;;
    esac
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            # Process is dead, remove PID file
            rm -f "$pid_file"
            return 1
        fi
    fi
    return 1
}

# Function to restart a service
restart_service() {
    local service_name=$1
    log_warn "Restarting $service_name..."
    
    case $service_name in
        dhcpd)
            pkill -f dhcpd 2>/dev/null || true
            rm -f /var/run/dhcpd.pid
            sleep 2
            start_service dhcpd
            ;;
        tftp)
            pkill -f tftpd 2>/dev/null || true
            rm -f /var/run/in.tftpd.pid
            sleep 2
            start_service tftp
            ;;
    esac
}

# Main startup sequence
main() {
    log_info "Starting PXE Server..."
    
    # Configure services first
    configure_dhcp
    setup_tftp
    
    # Start essential services
    start_service chronyd
    start_service dhcpd
    start_service tftp
    
    # Enable services for future boots
    enable_service chronyd
    enable_service firewalld
    enable_service dhcpd
    enable_service tftp
    
    # Configure firewall rules (skip in Docker to avoid DBUS issues)
    log_info "Firewall configuration skipped in Docker container"
    log_info "Ports will be managed by Docker port mappings"
    
    # Display service status
    log_info "Service Status:"
    echo "=========================================="
    # Use basic commands available in minimal images
    if [ -f /proc/1/comm ]; then
        for proc in /proc/*/comm; do
            if grep -q chronyd "$proc" 2>/dev/null; then
                echo "chronyd is running"
                break
            fi
        done
    else
        echo "chronyd status unknown"
    fi
    echo "=========================================="
    echo "firewalld not running (disabled in Docker)"
    echo "=========================================="
    if check_service dhcpd; then
        echo "dhcpd is running (PID: $(cat /var/run/dhcpd.pid))"
    else
        echo "dhcpd not running"
    fi
    echo "=========================================="
    if check_service tftp; then
        echo "tftp is running (PID: $(cat /var/run/in.tftpd.pid))"
    else
        echo "tftp not running"
    fi
    echo "=========================================="
    
    log_info "PXE Server startup complete!"
    log_info "Services are running and ready for PXE boot requests."
    
    # Keep the container running and monitor services
    log_info "Container is running. Press Ctrl+C to stop."
    while true; do
        sleep 30
        
        # Check if critical services are still running
        local dhcpd_running=false
        local tftp_running=false
        
        # Check DHCP
        if check_service dhcpd; then
            dhcpd_running=true
        fi
        
        # Check TFTP
        if check_service tftp; then
            tftp_running=true
        fi
        
        # Only restart DHCP if it's down (TFTP is optional for basic PXE)
        if [ "$dhcpd_running" = false ]; then
            log_warn "DHCP service stopped. Restarting..."
            restart_service dhcpd
        fi
        
        # Only restart TFTP if both services are down (emergency restart)
        if [ "$dhcpd_running" = false ] && [ "$tftp_running" = false ]; then
            log_error "Critical services stopped. Emergency restart..."
            restart_service dhcpd
            restart_service tftp
        fi
        
        # Log status every 5 minutes
        if [ $((SECONDS % 300)) -eq 0 ]; then
            log_info "Service status check - DHCP: $dhcpd_running, TFTP: $tftp_running"
        fi
    done
}

# Handle signals
trap 'log_info "Shutting down PXE Server..."; exit 0' SIGTERM SIGINT

# Run main function
main "$@"
