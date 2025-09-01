# PXE Server Troubleshooting Guide

This guide helps you resolve common issues with the PXE Telemetry & Diagnostics System.

## Common Issues and Solutions

### 1. Docker/Podman Connection Issues

**Problem**: `Cannot connect to the Docker daemon` or similar errors

**Solutions**:
- **Docker**: Start Docker service
  ```bash
  sudo systemctl start docker
  sudo systemctl enable docker
  ```
- **Podman**: Podman runs without a daemon, but you may need to start the socket
  ```bash
  sudo systemctl start podman.socket
  sudo systemctl enable podman.socket
  ```

### 2. Network Configuration Issues

**Problem**: Network overlaps with other address spaces

**Solution**: Clean up existing networks
```bash
# For Docker
docker network prune -f
docker network rm pxe_telemetry_diagnostics_pxe_network 2>/dev/null || true

# For Podman
podman network prune -f
podman network rm pxe_telemetry_diagnostics_pxe_network 2>/dev/null || true
```

### 3. Foreman Installation Failures

**Problem**: Foreman installer fails with various errors

**Solution**: The setup has been simplified to focus on core PXE functionality without Foreman. This eliminates:
- Hostname configuration issues
- Reverse DNS problems
- IPv6 conflicts
- System encoding issues

### 4. Service Startup Issues

**Problem**: DHCP or TFTP services fail to start

**Solutions**:
- Check if ports are already in use:
  ```bash
  sudo netstat -tulpn | grep -E ":67|:69"
  ```
- Kill conflicting processes:
  ```bash
  sudo pkill -f dhcpd
  sudo pkill -f tftpd
  ```
- Restart the PXE server container:
  ```bash
  sudo docker restart pxe_server
  # or
  sudo podman restart pxe_server
  ```

### 5. PXE Boot File Issues

**Problem**: Missing PXE boot files

**Solution**: Build the PXE image
```bash
cd pxe_image
sudo ./build_image.sh
```

### 6. Container Build Failures

**Problem**: Docker/Podman build fails

**Solutions**:
- Clean up Docker cache:
  ```bash
  docker system prune -a
  # or
  podman system prune -a
  ```
- Check available disk space:
  ```bash
  df -h
  ```
- Ensure you have sufficient memory (at least 2GB free)

### 7. Permission Issues

**Problem**: Permission denied errors

**Solution**: Ensure you're running as root or with sudo
```bash
sudo ./setup.sh
sudo ./scripts/test_pxe.sh
```

### 8. Port Conflicts

**Problem**: Ports already in use

**Solutions**:
- Check what's using the ports:
  ```bash
  sudo netstat -tulpn | grep -E ":67|:69|:5000|:3000"
  ```
- Stop conflicting services:
  ```bash
  sudo systemctl stop dhcpd  # if running system DHCP
  sudo systemctl stop tftp   # if running system TFTP
  ```

## Diagnostic Commands

### Check Container Status
```bash
# Docker
docker ps -a
docker logs pxe_server
docker logs main_program

# Podman
podman ps -a
podman logs pxe_server
podman logs main_program
```

### Check Service Status
```bash
# Check if services are listening
sudo netstat -tulpn | grep -E ":67|:69|:5000"

# Check DHCP server
sudo docker exec pxe_server netstat -tulpn | grep :67
sudo podman exec pxe_server netstat -tulpn | grep :67

# Check TFTP server
sudo docker exec pxe_server netstat -tulpn | grep :69
sudo podman exec pxe_server netstat -tulpn | grep :69
```

### Test Network Connectivity
```bash
# Test DHCP
sudo dhclient -v test0  # Create test interface first

# Test TFTP
curl -s tftp://localhost:69/boot.ipxe

# Test API
curl -s http://localhost:5000/api/v1/health
```

### Check PXE Boot Files
```bash
# List TFTP directory contents
sudo docker exec pxe_server ls -la /var/lib/tftpboot/
sudo podman exec pxe_server ls -la /var/lib/tftpboot/

# Check specific files
sudo docker exec pxe_server test -f /var/lib/tftpboot/vmlinuz-virt && echo "Kernel exists" || echo "Kernel missing"
sudo docker exec pxe_server test -f /var/lib/tftpboot/initramfs-virt && echo "Initramfs exists" || echo "Initramfs missing"
```

## Recovery Procedures

### Complete Reset
If the system is in a bad state, perform a complete reset:

```bash
# Stop all containers
sudo docker-compose down
# or
sudo podman-compose down

# Remove all containers and networks
sudo docker system prune -a -f
# or
sudo podman system prune -a -f

# Clean up volumes (WARNING: This will delete all data)
sudo docker volume prune -f
# or
sudo podman volume prune -f

# Restart from scratch
sudo ./setup.sh
```

### Manual Service Recovery
If specific services are failing:

```bash
# Restart PXE server container
sudo docker restart pxe_server
# or
sudo podman restart pxe_server

# Manually start services inside container
sudo docker exec pxe_server /usr/local/bin/start_pxe_server.sh
# or
sudo podman exec pxe_server /usr/local/bin/start_pxe_server.sh
```

## Log Analysis

### Common Log Patterns

**DHCP Server Issues**:
- Look for "No subnet declaration" - indicates DHCP configuration problem
- Look for "address already in use" - indicates port conflict

**TFTP Server Issues**:
- Look for "permission denied" - indicates file permission problems
- Look for "file not found" - indicates missing boot files

**Container Issues**:
- Look for "executable not found" - indicates missing packages
- Look for "address already in use" - indicates port conflicts

### Log Locations
```bash
# Container logs
sudo docker logs pxe_server
sudo docker logs main_program

# System logs
sudo journalctl -u docker
sudo journalctl -u podman

# Service logs (inside container)
sudo docker exec pxe_server cat /var/log/pxe/dhcpd.log
sudo docker exec pxe_server cat /var/log/pxe/tftpd.log
```

## Performance Optimization

### Memory Issues
If containers are running out of memory:
```bash
# Increase Docker memory limit
# Edit /etc/docker/daemon.json
{
  "default-memory": "2g",
  "default-memory-swap": "4g"
}

# Restart Docker
sudo systemctl restart docker
```

### Disk Space Issues
If running out of disk space:
```bash
# Clean up Docker images and containers
sudo docker system prune -a -f

# Clean up old logs
sudo find /var/log -name "*.log" -mtime +7 -delete
```

## Getting Help

If you're still experiencing issues:

1. Run the test script: `sudo ./scripts/test_pxe.sh`
2. Collect logs: `sudo docker logs pxe_server > pxe_server.log`
3. Check system resources: `top`, `df -h`, `free -h`
4. Verify network configuration: `ip addr show`, `ip route show`

Include the following information when seeking help:
- Operating system and version
- Docker/Podman version
- Complete error messages
- Output from test script
- System resource usage
- Network configuration
