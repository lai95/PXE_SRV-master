#!/bin/bash

# Native PXE Server Test Script
# Tests the native PXE server installation

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

# Test DHCP server
test_dhcp() {
    log_section "Testing DHCP Server"
    
    # Check if DHCP is running
    if systemctl is-active dhcpd >/dev/null 2>&1; then
        log_info "DHCP server is running"
    else
        log_error "DHCP server is not running"
        return 1
    fi
    
    # Check if DHCP is listening
    if netstat -tulpn 2>/dev/null | grep -q ":67 "; then
        log_info "DHCP server is listening on port 67"
    else
        log_error "DHCP server is not listening on port 67"
        return 1
    fi
}

# Test TFTP server
test_tftp() {
    log_section "Testing TFTP Server"
    
    # Check if TFTP is running
    if systemctl is-active tftp >/dev/null 2>&1; then
        log_info "TFTP server is running"
    else
        log_error "TFTP server is not running"
        return 1
    fi
    
    # Check if TFTP is listening
    if netstat -tulpn 2>/dev/null | grep -q ":69 "; then
        log_info "TFTP server is listening on port 69"
    else
        log_error "TFTP server is not listening on port 69"
        return 1
    fi
    
    # Test TFTP file access
    if [ -f "/var/lib/tftpboot/menu.ipxe" ]; then
        log_info "TFTP boot files exist"
    else
        log_warn "TFTP boot files missing"
    fi
}

# Test API server
test_api() {
    log_section "Testing API Server"
    
    # Check if API is running
    if systemctl is-active pxe-api >/dev/null 2>&1; then
        log_info "API server is running"
    else
        log_error "API server is not running"
        return 1
    fi
    
    # Test API health endpoint
    if curl -s http://localhost:5000/api/v1/health >/dev/null 2>&1; then
        log_info "API health endpoint is responding"
    else
        log_error "API health endpoint is not responding"
        return 1
    fi
}

# Test services
test_services() {
    log_section "Testing Services"
    
    local services=("dhcpd" "tftp" "pxe-api" "firewalld" "chronyd")
    local failed_services=()
    
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            log_info "$service is running"
        else
            log_error "$service is not running"
            failed_services+=("$service")
        fi
    done
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        log_warn "Failed services: ${failed_services[*]}"
        return 1
    fi
}

# Test network configuration
test_network() {
    log_section "Testing Network Configuration"
    
    # Check if server IP is configured
    if ip addr show | grep -q "192.168.1.1"; then
        log_info "Server IP 192.168.1.1 is configured"
    else
        log_warn "Server IP 192.168.1.1 is not configured (this is normal if using different IP)"
    fi
    
    # Check firewall rules
    if firewall-cmd --list-services | grep -q "dhcp"; then
        log_info "DHCP service is allowed in firewall"
    else
        log_warn "DHCP service not found in firewall rules"
    fi
    
    if firewall-cmd --list-services | grep -q "tftp"; then
        log_info "TFTP service is allowed in firewall"
    else
        log_warn "TFTP service not found in firewall rules"
    fi
}

# Test PXE boot files
test_pxe_files() {
    log_section "Testing PXE Boot Files"
    
    local tftp_dir="/var/lib/tftpboot"
    local required_files=("vmlinuz-virt" "initramfs-virt" "menu.ipxe")
    local missing_files=()
    
    if [ -d "$tftp_dir" ]; then
        log_info "TFTP directory exists: $tftp_dir"
        
        for file in "${required_files[@]}"; do
            if [ -f "$tftp_dir/$file" ]; then
                log_info "✓ $file exists"
            else
                log_warn "✗ $file missing"
                missing_files+=("$file")
            fi
        done
        
        if [ ${#missing_files[@]} -eq 0 ]; then
            log_info "All required PXE boot files are present"
        else
            log_warn "Missing PXE boot files: ${missing_files[*]}"
        fi
    else
        log_error "TFTP directory does not exist: $tftp_dir"
        return 1
    fi
}

# Main test function
main() {
    log_info "Starting Native PXE Server Tests"
    
    check_root
    
    test_services
    test_dhcp
    test_tftp
    test_api
    test_network
    test_pxe_files
    
    log_info "Native PXE Server tests completed"
    log_info "If all tests pass, your PXE server should be ready for boot requests"
}

# Run main function
main "$@"
