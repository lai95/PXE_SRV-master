#!/bin/bash

# PXE Server Test Script
# This script tests the PXE server functionality

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
    
    # Check if DHCP server is listening on port 67
    if netstat -tulpn 2>/dev/null | grep -q ":67 "; then
        log_info "DHCP server is listening on port 67"
    else
        log_error "DHCP server is not listening on port 67"
        return 1
    fi
    
    # Test DHCP server with dhclient (if available)
    if command -v dhclient &> /dev/null; then
        log_info "Testing DHCP server with dhclient..."
        
        # Create a temporary interface for testing
        ip link add test0 type dummy 2>/dev/null || true
        ip addr add 192.168.1.50/24 dev test0 2>/dev/null || true
        
        # Try to get DHCP lease
        timeout 10 dhclient -v test0 2>&1 | grep -q "DHCPACK" && {
            log_info "DHCP server responded with lease"
        } || {
            log_warn "DHCP server did not respond (this may be normal if no DHCP server is configured for this interface)"
        }
        
        # Clean up
        ip link del test0 2>/dev/null || true
    else
        log_warn "dhclient not available, skipping DHCP test"
    fi
}

# Test TFTP server
test_tftp() {
    log_section "Testing TFTP Server"
    
    # Check if TFTP server is listening on port 69
    if netstat -tulpn 2>/dev/null | grep -q ":69 "; then
        log_info "TFTP server is listening on port 69"
    else
        log_error "TFTP server is not listening on port 69"
        return 1
    fi
    
    # Test TFTP server with curl (if available)
    if command -v curl &> /dev/null; then
        log_info "Testing TFTP server with curl..."
        
        # Try to download a file from TFTP
        if curl -s --connect-timeout 5 tftp://localhost:69/boot.ipxe &> /dev/null; then
            log_info "TFTP server responded to file request"
        else
            log_warn "TFTP server did not respond to file request (file may not exist)"
        fi
    else
        log_warn "curl not available, skipping TFTP test"
    fi
}

# Test PXE boot files
test_pxe_files() {
    log_section "Testing PXE Boot Files"
    
    # Check if PXE boot files exist
    local tftp_dir="/var/lib/tftpboot"
    
    if [ -d "$tftp_dir" ]; then
        log_info "TFTP directory exists: $tftp_dir"
        
        # List files in TFTP directory
        log_info "Files in TFTP directory:"
        ls -la "$tftp_dir" 2>/dev/null || log_warn "Cannot list TFTP directory"
        
        # Check for essential PXE files
        local essential_files=("vmlinuz-virt" "initramfs-virt" "menu.ipxe" "boot.ipxe")
        local missing_files=()
        
        for file in "${essential_files[@]}"; do
            if [ -f "$tftp_dir/$file" ]; then
                log_info "✓ $file exists"
            else
                log_warn "✗ $file missing"
                missing_files+=("$file")
            fi
        done
        
        if [ ${#missing_files[@]} -eq 0 ]; then
            log_info "All essential PXE boot files are present"
        else
            log_warn "Missing PXE boot files: ${missing_files[*]}"
            log_info "Run: cd pxe_image && sudo ./build_image.sh"
        fi
    else
        log_error "TFTP directory does not exist: $tftp_dir"
        return 1
    fi
}

# Test network connectivity
test_network() {
    log_section "Testing Network Connectivity"
    
    # Check if we can reach the PXE server
    if ping -c 1 192.168.1.2 &> /dev/null; then
        log_info "PXE server (192.168.1.2) is reachable"
    else
        log_warn "PXE server (192.168.1.2) is not reachable"
    fi
    
    # Check if we can reach the gateway
    if ping -c 1 192.168.1.1 &> /dev/null; then
        log_info "Gateway (192.168.1.1) is reachable"
    else
        log_warn "Gateway (192.168.1.1) is not reachable"
    fi
}

# Test container status
test_containers() {
    log_section "Testing Container Status"
    
    # Check if containers are running
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        log_info "Checking Docker containers..."
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(pxe_server|main_program)" || {
            log_warn "No PXE-related containers found"
        }
    elif command -v podman &> /dev/null && podman info &> /dev/null; then
        log_info "Checking Podman containers..."
        podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(pxe_server|main_program)" || {
            log_warn "No PXE-related containers found"
        }
    else
        log_warn "No container runtime found"
    fi
}

# Test API server
test_api() {
    log_section "Testing API Server"
    
    # Check if API server is responding
    if curl -s --connect-timeout 5 http://localhost:5000/api/v1/health &> /dev/null; then
        log_info "API server is responding on port 5000"
    else
        log_warn "API server is not responding on port 5000"
    fi
}

# Main test function
main() {
    log_info "Starting PXE Server Tests"
    
    # Check if running as root
    check_root
    
    # Run tests
    test_containers
    test_network
    test_dhcp
    test_tftp
    test_pxe_files
    test_api
    
    log_info "PXE Server tests completed"
    log_info "If all tests pass, your PXE server should be ready for boot requests"
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo ""
        echo "This script tests the PXE server functionality including:"
        echo "- Container status"
        echo "- Network connectivity"
        echo "- DHCP server"
        echo "- TFTP server"
        echo "- PXE boot files"
        echo "- API server"
        ;;
    *)
        main "$@"
        ;;
esac
