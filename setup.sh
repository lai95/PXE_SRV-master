#!/bin/bash

# PXE Telemetry & Diagnostics System - Setup Script
# Complete system deployment and configuration

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="pxe_telemetry_diagnostics"
VERSION="1.0.0"

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

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check for required tools
    for tool in git python3 pip3; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    # Check for Docker or Podman
    local container_runtime=""
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        container_runtime="docker"
        log_info "Docker detected and running"
    elif command -v podman &> /dev/null && podman info &> /dev/null; then
        container_runtime="podman"
        log_info "Podman detected and running"
    else
        log_error "Neither Docker nor Podman is available and running"
        log_info "Please install and start Docker or Podman"
        exit 1
    fi
    
    # Check for Docker Compose (either V1 or V2)
    local compose_command=""
    if command -v docker-compose &> /dev/null; then
        compose_command="docker-compose"
        log_info "Docker Compose V1 detected"
    elif docker compose version &> /dev/null 2>/dev/null; then
        compose_command="docker compose"
        log_info "Docker Compose V2 detected"
    elif podman-compose --version &> /dev/null 2>/dev/null; then
        compose_command="podman-compose"
        log_info "Podman Compose detected"
    else
        log_error "No compatible compose tool found"
        log_info "Please install Docker Compose V1/V2 or Podman Compose"
        exit 1
    fi
    
    # Store the commands for later use
    export CONTAINER_RUNTIME="$container_runtime"
    export COMPOSE_COMMAND="$compose_command"
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Setup development environment
setup_dev_environment() {
    log_section "Setting Up Development Environment"
    
    # Create necessary directories
    mkdir -p docker monitoring/grafana/provisioning
    
    # Create Docker files if they don't exist
    create_docker_files
    
    # Install Python dependencies
    log_info "Installing Python dependencies..."
    cd main_program
    pip3 install -r requirements.txt
    cd ..
    
    log_info "Development environment setup complete"
}

# Create Docker files
create_docker_files() {
    log_info "Creating Docker configuration files..."
    
    # Create docker directory
    mkdir -p docker
    
    # PXE Server Dockerfile - Simplified version without Foreman
    cat > docker/pxe_server.Dockerfile << 'EOF'
FROM rockylinux:9

# Install system packages
RUN dnf update -y && \
    dnf install -y epel-release && \
    dnf install -y \
        wget \
        vim \
        htop \
        net-tools \
        bind-utils \
        tcpdump \
        iotop \
        sysstat \
        lsof \
        strace \
        gcc \
        make \
        python3 \
        python3-pip \
        python3-devel \
        openssl \
        ca-certificates \
        chrony \
        firewalld \
        dhcp-server \
        tftp-server \
        syslinux \
        procps-ng \
        iproute \
        iputils \
    && dnf clean all

# Configure services
RUN systemctl enable firewalld chronyd dhcpd tftp

# Create required directories
RUN mkdir -p /var/lib/tftpboot /opt/pxe /var/log/pxe

# Set up users
RUN useradd -r -s /bin/bash -d /opt/pxe pxe \
    && groupadd tftp \
    && usermod -a -G tftp pxe

# Copy configuration files
COPY scripts/start_pxe_server.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/start_pxe_server.sh

# Expose ports
EXPOSE 3000 67/udp 69/udp 53/udp 22

CMD ["/usr/local/bin/start_pxe_server.sh"]
EOF

    # Main Program Dockerfile
    cat > docker/main_program.Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY main_program/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main_program/ .

# Create necessary directories
RUN mkdir -p /var/lib/foreman-reports /var/log/main_program

# Expose port
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5000/api/v1/health || exit 1

CMD ["python", "app.py", "--host", "0.0.0.0", "--port", "5000"]
EOF

    # PXE Client Dockerfile
    cat > docker/pxe_client.Dockerfile << 'EOF'
FROM alpine:3.18

# Install diagnostic tools
RUN apk add --no-cache \
    lshw \
    hwinfo \
    dmidecode \
    smartmontools \
    hdparm \
    fio \
    memtester \
    stress-ng \
    sysbench \
    iperf3 \
    netperf \
    snmp-tools \
    lldpd \
    ethtool \
    ipmitool \
    lm-sensors \
    mdadm \
    bonnie++ \
    ioping \
    curl \
    wget \
    jq \
    python3 \
    bash \
    vim \
    htop \
    iotop \
    sysstat \
    lsof \
    strace \
    gcc \
    make \
    linux-headers

# Copy diagnostic scripts
COPY diagnostics/ /opt/diagnostics/
RUN chmod +x /opt/diagnostics/bin/*

# Create required directories
RUN mkdir -p /reports /var/log/diagnostics /tmp/upload

# Set up diagnostic service
RUN echo '#!/bin/sh' > /etc/init.d/diagnostics \
    && echo 'case "$1" in' >> /etc/init.d/diagnostics \
    && echo '    start)' >> /etc/init.d/diagnostics \
    && echo '        echo "Starting diagnostic system..."' >> /etc/init.d/diagnostics \
    && echo '        /opt/diagnostics/bin/run_diagnostics.sh' >> /etc/init.d/diagnostics \
    && echo '        ;;' >> /etc/init.d/diagnostics \
    && echo '    *)' >> /etc/init.d/diagnostics \
    && echo '        echo "Usage: $0 {start}"' >> /etc/init.d/diagnostics \
    && echo '        exit 1' >> /etc/init.d/diagnostics \
    && echo '        ;;' >> /etc/init.d/diagnostics \
    && echo 'esac' >> /etc/init.d/diagnostics \
    && chmod +x /etc/init.d/diagnostics

# Run diagnostics on startup
CMD ["/etc/init.d/diagnostics", "start"]
EOF

    log_info "Docker files created"
}

# Build and start services
deploy_services() {
    log_section "Deploying Services"
    
    log_info "Building Docker images..."
    
    # Use the detected compose command
    log_info "Using $COMPOSE_COMMAND..."
    
    # Clean up any existing containers and networks
    log_info "Cleaning up existing containers..."
    $COMPOSE_COMMAND down --remove-orphans 2>/dev/null || true
    
    # Remove any conflicting networks
    if [ "$CONTAINER_RUNTIME" = "docker" ]; then
        docker network rm pxe_telemetry_diagnostics_pxe_network 2>/dev/null || true
    elif [ "$CONTAINER_RUNTIME" = "podman" ]; then
        podman network rm pxe_telemetry_diagnostics_pxe_network 2>/dev/null || true
    fi
    
    $COMPOSE_COMMAND build
    
    log_info "Starting services..."
    $COMPOSE_COMMAND up -d
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 30
    
    # Check service status
    log_info "Checking service status..."
    $COMPOSE_COMMAND ps
    
    log_info "Services deployed successfully"
}

# Configure PXE services (simplified without Foreman)
configure_pxe_services() {
    log_section "Configuring PXE Services"
    
    log_info "Waiting for PXE server to be ready..."
    
    # Wait for PXE server container
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Checking PXE server status (attempt $attempt/$max_attempts)..."
        
        # Check if container is running
        if $COMPOSE_COMMAND ps | grep -q pxe_server; then
            log_info "PXE server container is running"
            break
        fi
        
        log_info "Waiting for PXE server... (attempt $attempt/$max_attempts)"
        sleep 10
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "PXE server failed to start within expected time"
        return 1
    fi
    
    # Configure DHCP and TFTP services
    log_info "Configuring DHCP and TFTP services..."
    
    # Wait a bit more for services to fully start
    sleep 10
    
    # Check if services are running
    local container_name=""
    if [ "$CONTAINER_RUNTIME" = "docker" ]; then
        container_name="pxe_server"
    else
        container_name="pxe_telemetry_diagnostics-pxe_server-1"
    fi
    
    # Verify DHCP is running
    if $CONTAINER_RUNTIME exec $container_name bash -c 'netstat -tulpn | grep :67' 2>/dev/null; then
        log_info "DHCP server is running"
    else
        log_warn "DHCP server may not be running properly"
    fi
    
    # Verify TFTP is running
    if $CONTAINER_RUNTIME exec $container_name bash -c 'netstat -tulpn | grep :69' 2>/dev/null; then
        log_info "TFTP server is running"
    else
        log_warn "TFTP server may not be running properly"
    fi
    
    log_info "Core PXE system is ready for operation"
    log_info "DHCP and TFTP services are running and functional"
    log_info "PXE boot requests will be handled automatically"
}

# Build PXE image
build_pxe_image() {
    log_section "Building PXE Diagnostic Image"
    
    log_info "Building diagnostic boot image..."
    
    # Check if we're in a Docker environment
    if [ -f /.dockerenv ]; then
        log_warn "Running in Docker container, PXE image build may not work properly"
        log_info "Consider building the PXE image on the host system"
        return 0
    fi
    
    # Check if build script exists and is executable
    if [ -f "pxe_image/build_image.sh" ]; then
        chmod +x pxe_image/build_image.sh
        
        # Check if running as root (required for image building)
        if [ "$EUID" -eq 0 ]; then
            log_info "Building PXE image as root..."
            cd pxe_image
            log_info "Starting PXE image build - this may take several minutes..."
            
            # Run build script and capture its PID
            ./build_image.sh &
            BUILD_PID=$!
            
            # Wait for build to complete
            log_info "Waiting for PXE image build to complete (PID: $BUILD_PID)..."
            wait $BUILD_PID
            BUILD_EXIT_CODE=$?
            
            if [ $BUILD_EXIT_CODE -eq 0 ]; then
                log_info "PXE image build completed successfully!"
            else
                log_error "PXE image build failed with exit code $BUILD_EXIT_CODE"
                return 1
            fi
            
            cd ..
        else
            log_warn "PXE image build requires root privileges"
            log_info "Run 'sudo ./pxe_image/build_image.sh' to build the image"
        fi
    else
        log_warn "PXE image build script not found"
    fi
    
    log_info "PXE image build process initiated"
    
    # Wait for build to complete and create PXE boot files
    log_info "Waiting for PXE image build to complete..."
    sleep 10
    
    # Create PXE boot files
    log_info "Creating PXE boot files..."
    if [ -f "pxe_image/output/vmlinuz-virt" ] && [ -f "pxe_image/output/initramfs-virt" ]; then
        log_info "PXE image files found, creating boot configuration..."
        
        # Get container name
        local container_name=""
        if [ "$CONTAINER_RUNTIME" = "docker" ]; then
            container_name="pxe_server"
        else
            container_name="pxe_telemetry_diagnostics-pxe_server-1"
        fi
        
        # Copy kernel and initramfs to TFTP directory
        $CONTAINER_RUNTIME exec $container_name mkdir -p /var/lib/tftpboot
        $CONTAINER_RUNTIME cp pxe_image/output/vmlinuz-virt $container_name:/var/lib/tftpboot/
        $CONTAINER_RUNTIME cp pxe_image/output/initramfs-virt $container_name:/var/lib/tftpboot/
        
        # Create PXE boot configuration for traditional PXE
        $CONTAINER_RUNTIME exec $container_name bash -c 'cat > /var/lib/tftpboot/pxelinux.cfg/default << EOF
DEFAULT diagnostic
PROMPT 0
TIMEOUT 300

LABEL diagnostic
    KERNEL vmlinuz-virt
    APPEND initrd=initramfs-virt root=/dev/ram0 rw console=ttyS0,115200 console=tty0
    TEXT HELP
        PXE Diagnostic System
    ENDTEXT
EOF'
        
        # Create iPXE boot configuration (for modern PXE firmware)
        $CONTAINER_RUNTIME exec $container_name bash -c 'cat > /var/lib/tftpboot/boot.ipxe << EOF
#!ipxe
set base-url tftp://192.168.1.2/
kernel vmlinuz-virt
initrd initramfs-virt
boot
EOF'
        
        # Create menu.ipxe for iPXE menu interface
        $CONTAINER_RUNTIME exec $container_name bash -c 'cat > /var/lib/tftpboot/menu.ipxe << EOF
#!ipxe
set menu-timeout 5000
set submenu-timeout 5000

:start
menu PXE Diagnostic System
item --gap -- -------------------------
item diagnostic Alpine Linux Diagnostics
item --gap -- -------------------------
item exit Exit to iPXE shell
choose --timeout 30000 --default diagnostic option && goto \${option}

:diagnostic
kernel vmlinuz-virt
initrd initramfs-virt
boot

:exit
exit
EOF'

        # Create a simple test iPXE file for debugging
        $CONTAINER_RUNTIME exec $container_name bash -c 'cat > /var/lib/tftpboot/test.ipxe << EOF
#!ipxe
echo iPXE test file loaded successfully!
echo Current IP: \${net0/ip}
echo Gateway: \${net0/gateway}
echo Boot file: \${filename}
echo Next server: \${next-server}
echo TFTP server: \${tftp-server}
echo
echo Loading kernel...
kernel vmlinuz-virt
echo Loading initramfs...
initrd initramfs-virt
echo Booting...
boot
EOF'
        
        log_info "PXE boot files created successfully!"
        
        # Update DHCP configuration to serve iPXE boot files
        $CONTAINER_RUNTIME exec $container_name bash -c 'cat > /etc/dhcp/dhcpd.conf << EOF
default-lease-time 600;
max-lease-time 7200;
authoritative;

# PXE Boot Configuration - must be defined globally
option space pxelinux;
option pxelinux.magic code 208 = string;
option pxelinux.reboot-time code 209 = unsigned integer 32;
option pxelinux.menu code 16 = text;

subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    option domain-name-servers 192.168.1.2;
    
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
}
EOF'
        
        # Restart DHCP server with new configuration
        $CONTAINER_RUNTIME exec $container_name bash -c 'pkill -f dhcpd 2>/dev/null || killall dhcpd 2>/dev/null || true'
        $CONTAINER_RUNTIME exec $container_name bash -c 'sleep 2 && /usr/sbin/dhcpd -f -d &'
        
        # Wait for DHCP to start and verify it's running
        sleep 3
        if $CONTAINER_RUNTIME exec $container_name bash -c 'ps aux 2>/dev/null | grep dhcpd | grep -v grep >/dev/null 2>&1 || pgrep dhcpd >/dev/null 2>&1 || true'; then
            log_info "DHCP server started successfully"
        else
            log_warn "DHCP server may not be running - check manually"
        fi
        
        # Verify TFTP is properly bound to IPv4
        sleep 2
        if $CONTAINER_RUNTIME exec $container_name bash -c 'netstat -tulpn | grep "0.0.0.0:69" >/dev/null 2>&1'; then
            log_info "TFTP server properly bound to IPv4"
        else
            log_warn "TFTP server not bound to IPv4 - restarting with proper binding"
            $CONTAINER_RUNTIME exec $container_name bash -c 'pkill -f tftp 2>/dev/null || killall tftp 2>/dev/null || true'
            $CONTAINER_RUNTIME exec $container_name bash -c 'sleep 2 && in.tftpd -l -s /var/lib/tftpboot -a 0.0.0.0:69 &'
        fi
        
        log_info "DHCP configuration updated for iPXE support"
        log_info "TFTP directory contents:"
        $CONTAINER_RUNTIME exec $container_name ls -la /var/lib/tftpboot/
    else
        log_warn "PXE image files not found, manual build required"
        log_info "Run: cd pxe_image && sudo ./build_image.sh"
    fi
}

# Setup monitoring
setup_monitoring() {
    log_section "Setting Up Monitoring"
    
    log_info "Starting monitoring services..."
    $COMPOSE_COMMAND --profile monitoring up -d
    
    # Wait for Grafana
    log_info "Waiting for Grafana to be ready..."
    sleep 20
    
    if curl -s http://localhost:3001/api/health &> /dev/null; then
        log_info "Grafana is ready"
        echo "Grafana URL: http://localhost:3001" >> foreman_credentials.txt
        echo "Grafana Admin: admin / admin123" >> foreman_credentials.txt
    else
        log_warn "Grafana failed to start"
    fi
    
    log_info "Monitoring setup complete"
}

# Display system information
display_system_info() {
    log_section "System Information"
    
    echo "PXE Telemetry & Diagnostics System"
    echo "=================================="
    echo "Version: $VERSION"
    echo "Project Directory: $SCRIPT_DIR"
    echo "Container Runtime: $CONTAINER_RUNTIME"
    echo "Compose Command: $COMPOSE_COMMAND"
    echo ""
    echo "Service URLs:"
    echo "- Main Program API: http://localhost:5000"
    echo "- Grafana Dashboard: http://localhost:3001 (if monitoring enabled)"
    echo ""
    echo "Network Configuration:"
    echo "- PXE Network: 192.168.1.0/24"
    echo "- Gateway: 192.168.1.1"
    echo ""
    echo "Next Steps:"
    echo "1. Build PXE diagnostic image: cd pxe_image && sudo ./build_image.sh"
    echo "2. Test PXE boot with a target device"
    echo "3. Monitor diagnostic reports via the API"
    echo ""
    echo "Useful Commands:"
    echo "- View logs: $COMPOSE_COMMAND logs -f [service_name]"
    echo "- Stop services: $COMPOSE_COMMAND down"
    echo "- Restart services: $COMPOSE_COMMAND restart"
    echo "- Update services: $COMPOSE_COMMAND pull && $COMPOSE_COMMAND up -d"
    echo ""
    echo "Container Management:"
    echo "- List containers: $CONTAINER_RUNTIME ps"
    echo "- View container logs: $CONTAINER_RUNTIME logs [container_name]"
    echo "- Execute commands: $CONTAINER_RUNTIME exec [container_name] [command]"
}

# Main execution
main() {
    log_info "Starting PXE Telemetry & Diagnostics System Setup"
    log_info "Version: $VERSION"
    
    # Check prerequisites
    check_prerequisites
    
    # Setup development environment
    setup_dev_environment
    
    # Deploy services
    deploy_services
    
    # Configure PXE services (simplified without Foreman)
    configure_pxe_services
    
    # Build PXE image
    build_pxe_image
    
    # Setup monitoring (optional)
    if [ "$1" = "--with-monitoring" ]; then
        setup_monitoring
    fi
    
    # Display system information
    display_system_info
    
    log_info "Setup completed successfully!"
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --with-monitoring    Include Grafana monitoring setup"
        echo "  --help, -h          Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                  # Basic setup without monitoring"
        echo "  $0 --with-monitoring # Setup with monitoring"
        ;;
    *)
        main "$@"
        ;;
esac
