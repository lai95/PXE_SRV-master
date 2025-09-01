#!/bin/bash

# Native PXE Server Setup Script
# Installs and configures PXE server directly on Rocky Linux

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_section() {
    echo -e "${BLUE}[SECTION]${NC} $1"
    echo "=========================================="
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Install system packages
install_packages() {
    log_section "Installing System Packages"
    
    log_info "Updating system packages..."
    dnf update -y
    
    log_info "Installing PXE server packages..."
    dnf install -y \
        dhcp-server \
        tftp-server \
        syslinux \
        python3 \
        python3-pip \
        git \
        wget \
        curl \
        net-tools \
        tcpdump \
        htop \
        vim \
        chrony \
        firewalld
    
    log_info "System packages installed successfully"
}

# Configure DHCP server
configure_dhcp() {
    log_section "Configuring DHCP Server"
    
    log_info "Creating DHCP configuration..."
    
    cat > /etc/dhcp/dhcpd.conf << 'EOF'
# DHCP Server Configuration for PXE
default-lease-time 600;
max-lease-time 7200;
authoritative;

# PXE Boot Configuration
option space pxelinux;
option pxelinux.magic code 208 = string;
option pxelinux.reboot-time code 209 = unsigned integer 32;
option pxelinux.menu code 16 = text;

# PXE Network Configuration
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    option domain-name-servers 192.168.1.1;
    option broadcast-address 192.168.1.255;
    
    # iPXE Configuration
    if exists user-class and option user-class = "iPXE" {
        filename "menu.ipxe";
        next-server 192.168.1.1;
    } elsif option vendor-class-identifier = "PXEClient:Arch:00000:UNDI:002001" {
        filename "pxelinux.0";
        next-server 192.168.1.1;
    } else {
        filename "menu.ipxe";
        next-server 192.168.1.1;
    }
    
    # Additional PXE options
    option tftp-server-name "192.168.1.1";
    option bootfile-name "pxelinux.0";
    
    # Allow booting
    allow booting;
    allow bootp;
}
EOF
    
    log_info "DHCP configuration created"
}

# Setup TFTP server
setup_tftp() {
    log_section "Setting Up TFTP Server"
    
    log_info "Creating TFTP directory..."
    mkdir -p /var/lib/tftpboot
    chmod 755 /var/lib/tftpboot
    chown root:root /var/lib/tftpboot
    
    # Create basic PXE structure
    mkdir -p /var/lib/tftpboot/pxelinux.cfg
    chmod 755 /var/lib/tftpboot/pxelinux.cfg
    
    log_info "TFTP directory setup complete"
}

# Configure firewall
configure_firewall() {
    log_section "Configuring Firewall"
    
    log_info "Starting and enabling firewalld..."
    systemctl start firewalld
    systemctl enable firewalld
    
    log_info "Opening required ports..."
    firewall-cmd --permanent --add-service=dhcp
    firewall-cmd --permanent --add-service=tftp
    firewall-cmd --permanent --add-port=5000/tcp
    firewall-cmd --reload
    
    log_info "Firewall configured"
}

# Start and enable services
start_services() {
    log_section "Starting Services"
    
    log_info "Starting and enabling chronyd..."
    systemctl start chronyd
    systemctl enable chronyd
    
    log_info "Starting and enabling firewalld..."
    systemctl start firewalld
    systemctl enable firewalld
    
    log_info "Starting and enabling dhcpd..."
    systemctl start dhcpd
    systemctl enable dhcpd
    
    log_info "Starting and enabling tftp..."
    systemctl start tftp
    systemctl enable tftp
    
    log_info "All services started and enabled"
}

# Install Python dependencies
install_python_deps() {
    log_section "Installing Python Dependencies"
    
    log_info "Installing Python packages..."
    pip3 install Flask==2.3.3 Flask-CORS==4.0.0 requests==2.31.0
    
    log_info "Python dependencies installed"
}

# Create simple API server
create_api_server() {
    log_section "Creating API Server"
    
    log_info "Creating API server script..."
    
    cat > /opt/pxe_api.py << 'EOF'
#!/usr/bin/env python3

from flask import Flask, jsonify
from flask_cors import CORS
import subprocess
import os
import datetime

app = Flask(__name__)
CORS(app)

@app.route('/api/v1/health')
def health():
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.datetime.now().isoformat(),
        'service': 'PXE Telemetry API'
    })

@app.route('/api/v1/status')
def status():
    try:
        # Check DHCP status
        dhcp_status = subprocess.run(['systemctl', 'is-active', 'dhcpd'], 
                                   capture_output=True, text=True).stdout.strip()
        
        # Check TFTP status
        tftp_status = subprocess.run(['systemctl', 'is-active', 'tftp'], 
                                   capture_output=True, text=True).stdout.strip()
        
        return jsonify({
            'dhcp_server': dhcp_status,
            'tftp_server': tftp_status,
            'timestamp': datetime.datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF
    
    chmod +x /opt/pxe_api.py
    
    # Create systemd service for API
    cat > /etc/systemd/system/pxe-api.service << 'EOF'
[Unit]
Description=PXE Telemetry API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt
ExecStart=/usr/bin/python3 /opt/pxe_api.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl start pxe-api
    systemctl enable pxe-api
    
    log_info "API server created and started"
}

# Build PXE image
build_pxe_image() {
    log_section "Building PXE Image"
    
    log_info "Checking if PXE image build script exists..."
    if [ -f "pxe_image/build_image.sh" ]; then
        log_info "Building PXE image..."
        chmod +x pxe_image/build_image.sh
        cd pxe_image
        ./build_image.sh
        cd ..
        
        # Copy files to TFTP directory
        if [ -f "pxe_image/output/vmlinuz-virt" ] && [ -f "pxe_image/output/initramfs-virt" ]; then
            log_info "Copying PXE files to TFTP directory..."
            cp pxe_image/output/vmlinuz-virt /var/lib/tftpboot/
            cp pxe_image/output/initramfs-virt /var/lib/tftpboot/
            
            # Create PXE boot configuration
            cat > /var/lib/tftpboot/pxelinux.cfg/default << 'EOF'
DEFAULT diagnostic
PROMPT 0
TIMEOUT 300

LABEL diagnostic
    KERNEL vmlinuz-virt
    APPEND initrd=initramfs-virt root=/dev/ram0 rw console=ttyS0,115200 console=tty0
    TEXT HELP
        PXE Diagnostic System
    ENDTEXT
EOF
            
            # Create iPXE configuration
            cat > /var/lib/tftpboot/menu.ipxe << 'EOF'
#!ipxe
set menu-timeout 5000
set submenu-timeout 5000

:start
menu PXE Diagnostic System
item --gap -- -------------------------
item diagnostic Alpine Linux Diagnostics
item --gap -- -------------------------
item exit Exit to iPXE shell
choose --timeout 30000 --default diagnostic option && goto ${option}

:diagnostic
kernel vmlinuz-virt
initrd initramfs-virt
boot

:exit
exit
EOF
            
            log_info "PXE boot files created successfully"
        else
            log_warn "PXE image files not found, manual build required"
        fi
    else
        log_warn "PXE image build script not found"
    fi
}

# Display system information
display_info() {
    log_section "System Information"
    
    echo "Native PXE Server Setup Complete!"
    echo "=================================="
    echo ""
    echo "Services:"
    echo "- DHCP Server: $(systemctl is-active dhcpd)"
    echo "- TFTP Server: $(systemctl is-active tftp)"
    echo "- API Server: $(systemctl is-active pxe-api)"
    echo ""
    echo "Network Configuration:"
    echo "- PXE Network: 192.168.1.0/24"
    echo "- Server IP: 192.168.1.1"
    echo "- Client Range: 192.168.1.100-200"
    echo ""
    echo "API Endpoints:"
    echo "- Health Check: http://localhost:5000/api/v1/health"
    echo "- Status: http://localhost:5000/api/v1/status"
    echo ""
    echo "TFTP Directory: /var/lib/tftpboot/"
    echo "DHCP Config: /etc/dhcp/dhcpd.conf"
    echo ""
    echo "Useful Commands:"
    echo "- Check services: systemctl status dhcpd tftp pxe-api"
    echo "- View logs: journalctl -u dhcpd -f"
    echo "- Test TFTP: tftp localhost 69"
    echo "- Test API: curl http://localhost:5000/api/v1/health"
}

# Main execution
main() {
    log_info "Starting Native PXE Server Setup"
    
    check_root
    install_packages
    configure_dhcp
    setup_tftp
    configure_firewall
    start_services
    install_python_deps
    create_api_server
    build_pxe_image
    display_info
    
    log_info "Native PXE server setup completed successfully!"
}

# Run main function
main "$@"
