# PXE Server Quick Start Guide (Fixed Version)

This guide provides a quick overview of the fixes made to resolve the PXE server setup issues.

## What Was Fixed

### 1. Docker/Podman Compatibility
- **Problem**: Script only worked with Docker, failed with Podman
- **Fix**: Added automatic detection of Docker or Podman runtime
- **Result**: Works with both Docker and Podman

### 2. Foreman Installation Issues
- **Problem**: Foreman installer failed with hostname, DNS, and encoding issues
- **Fix**: Removed Foreman dependency and focused on core PXE functionality
- **Result**: Simplified setup that works reliably in containers

### 3. Network Configuration Problems
- **Problem**: Network overlaps and resource busy errors
- **Fix**: Added proper network cleanup and container name detection
- **Result**: No more network conflicts

### 4. Service Startup Issues
- **Problem**: DHCP and TFTP services failed to start properly
- **Fix**: Improved service startup script with better error handling
- **Result**: More reliable service startup and monitoring

## Quick Setup (Fixed)

### Prerequisites
```bash
# Install Docker or Podman
sudo dnf install docker  # or podman

# Start Docker (if using Docker)
sudo systemctl start docker
sudo systemctl enable docker

# Install Docker Compose or Podman Compose
sudo dnf install docker-compose  # or podman-compose
```

### Run Setup
```bash
# Clone the repository
git clone <repository-url>
cd PXE_SRV-master

# Run the fixed setup script
sudo ./setup.sh
```

### Test the Setup
```bash
# Run the test script to verify everything is working
sudo ./scripts/test_pxe.sh
```

## What's Different Now

### Before (Broken)
- Required Docker specifically
- Tried to install Foreman (failed)
- Had network conflicts
- Services failed to start
- Complex error handling

### After (Fixed)
- Works with Docker or Podman
- Focuses on core PXE functionality
- Proper network management
- Reliable service startup
- Better error handling and recovery

## Core Features (Working)

### ✅ DHCP Server
- Serves IP addresses on 192.168.1.0/24 network
- Supports both traditional PXE and iPXE clients
- Automatic client detection and boot file selection

### ✅ TFTP Server
- Serves PXE boot files
- Supports kernel and initramfs downloads
- Proper file permissions and access

### ✅ PXE Boot System
- Traditional PXE support (pxelinux.0)
- Modern iPXE support (menu.ipxe)
- Automatic boot file selection based on client type

### ✅ API Server
- REST API for diagnostic reports
- Health check endpoint
- Containerized for easy deployment

### ✅ Monitoring (Optional)
- Grafana dashboard
- System metrics collection
- Optional monitoring profile

## Network Configuration

### PXE Network
- **Subnet**: 192.168.1.0/24
- **Gateway**: 192.168.1.1
- **PXE Server**: 192.168.1.2
- **Client Range**: 192.168.1.100-200

### Ports
- **67/udp**: DHCP server
- **69/udp**: TFTP server
- **5000/tcp**: API server
- **3001/tcp**: Grafana (if monitoring enabled)

## Testing PXE Boot

### 1. Build PXE Image
```bash
cd pxe_image
sudo ./build_image.sh
```

### 2. Configure Client
- Set client to boot from network
- Ensure client is on 192.168.1.0/24 network
- Client should receive IP from DHCP server

### 3. Boot Process
1. Client sends DHCP request
2. Server responds with IP and boot file
3. Client downloads boot file via TFTP
4. Client boots into diagnostic system

## Troubleshooting

### Common Issues
1. **Port conflicts**: Check if ports 67, 69 are in use
2. **Network issues**: Verify network configuration
3. **Missing files**: Build PXE image first
4. **Permission errors**: Run with sudo

### Quick Diagnostics
```bash
# Check container status
docker ps  # or podman ps

# Check service status
sudo netstat -tulpn | grep -E ":67|:69|:5000"

# Check PXE files
sudo docker exec pxe_server ls -la /var/lib/tftpboot/

# Run full test
sudo ./scripts/test_pxe.sh
```

## Next Steps

1. **Build PXE Image**: `cd pxe_image && sudo ./build_image.sh`
2. **Test Boot**: Configure a client to boot from network
3. **Monitor**: Check API for diagnostic reports
4. **Customize**: Modify boot files and configurations as needed

## Support

- **Troubleshooting Guide**: `docs/troubleshooting.md`
- **Test Script**: `scripts/test_pxe.sh`
- **Logs**: Check container logs for detailed information

The fixed version focuses on reliability and simplicity, removing the complex Foreman integration that was causing issues and providing a solid foundation for PXE boot services.
