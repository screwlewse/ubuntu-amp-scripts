#!/bin/bash
# =============================================================================
# AMP Server Complete Setup Script
# Description: Automated installation and configuration for AMP game server
# Author: AMP Automation Script
# Version: 2.0
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# =============================================================================
# Configuration Variables - MODIFY THESE
# =============================================================================

# AMP Configuration
AMP_USERNAME="admin"
AMP_PASSWORD="ChangeThisPassword123!"  # Change this!
AMP_SYSTEM_PASSWORD="SystemPassword123!"  # Change this!
AMP_EMAIL="your@email.com"  # Optional, for Let's Encrypt

# Network Configuration
STATIC_IP="192.168.1.100"  # Set your desired static IP
GATEWAY_IP="192.168.1.1"   # Your router's IP
INTERFACE_NAME=""  # Leave empty to auto-detect

# Server Configuration
SERVER_HOSTNAME="amp-server"  # Hostname for the server
ENABLE_HTTPS="n"  # Set to 'y' if you have a domain name
DOMAIN_NAME=""    # Required if ENABLE_HTTPS is 'y'

# Ports to open (add more as needed)
GAME_PORTS=(
    "8080/tcp"    # AMP Web Interface
    "7777/udp"    # ARK Game Port
    "7778/udp"    # ARK Query Port
    "27015/udp"   # ARK RCON Port
)

# =============================================================================
# Color Output Functions
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        log_warning "This script is designed for Ubuntu. Other distributions may work but are untested."
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# =============================================================================
# Network Configuration Functions
# =============================================================================

detect_network_interface() {
    if [[ -z "$INTERFACE_NAME" ]]; then
        INTERFACE_NAME=$(ip route | grep default | awk '{print $5}' | head -n1)
        log_info "Detected network interface: $INTERFACE_NAME"
    fi
}

configure_static_ip() {
    log_info "Configuring static IP address..."
    
    # Backup existing netplan config
    cp /etc/netplan/*.yaml /etc/netplan/backup-$(date +%Y%m%d-%H%M%S).yaml 2>/dev/null || true
    
    # Create new netplan configuration
    cat > /etc/netplan/01-netcfg.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE_NAME:
      dhcp4: no
      addresses:
        - $STATIC_IP/24
      gateway4: $GATEWAY_IP
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF

    # Apply configuration
    netplan apply
    log_success "Static IP configured: $STATIC_IP"
}

# =============================================================================
# System Configuration Functions
# =============================================================================

configure_hostname() {
    log_info "Setting hostname to $SERVER_HOSTNAME..."
    hostnamectl set-hostname "$SERVER_HOSTNAME"
    echo "127.0.1.1 $SERVER_HOSTNAME" >> /etc/hosts
}

configure_lid_behavior() {
    log_info "Configuring laptop lid behavior..."
    
    # Configure systemd-logind
    sed -i 's/#HandleLidSwitch=suspend/HandleLidSwitch=ignore/g' /etc/systemd/logind.conf
    sed -i 's/#HandleLidSwitchExternalPower=suspend/HandleLidSwitchExternalPower=ignore/g' /etc/systemd/logind.conf
    sed -i 's/#HandleLidSwitchDocked=ignore/HandleLidSwitchDocked=ignore/g' /etc/systemd/logind.conf
    
    # Add lines if they don't exist
    grep -q "HandleLidSwitch=ignore" /etc/systemd/logind.conf || echo "HandleLidSwitch=ignore" >> /etc/systemd/logind.conf
    grep -q "HandleLidSwitchExternalPower=ignore" /etc/systemd/logind.conf || echo "HandleLidSwitchExternalPower=ignore" >> /etc/systemd/logind.conf
    grep -q "HandleLidSwitchDocked=ignore" /etc/systemd/logind.conf || echo "HandleLidSwitchDocked=ignore" >> /etc/systemd/logind.conf
    
    systemctl restart systemd-logind.service
    log_success "Lid close behavior configured"
}

disable_power_management() {
    log_info "Disabling power management..."
    
    # Disable sleep targets
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
    
    # Install power management tools
    apt-get install -y linux-tools-common linux-tools-generic linux-tools-$(uname -r) 2>/dev/null || true
    
    # Set performance governor if available
    if command -v cpupower &> /dev/null; then
        cpupower frequency-set -g performance 2>/dev/null || true
    fi
    
    log_success "Power management disabled"
}

# =============================================================================
# System Update and Prerequisites
# =============================================================================

update_system() {
    log_info "Updating system packages..."
    apt-get update
    apt-get upgrade -y
    apt-get install -y \
        curl \
        wget \
        nano \
        htop \
        net-tools \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        unattended-upgrades
    
    # Configure automatic security updates
    echo 'Unattended-Upgrade::Automatic-Reboot "false";' > /etc/apt/apt.conf.d/50unattended-upgrades
    dpkg-reconfigure -plow unattended-upgrades
    
    log_success "System updated and prerequisites installed"
}

# =============================================================================
# Firewall Configuration
# =============================================================================

configure_firewall() {
    log_info "Configuring firewall..."
    
    # Install UFW
    apt-get install -y ufw
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow 22/tcp
    
    # Allow configured game ports
    for port in "${GAME_PORTS[@]}"; do
        log_info "Opening port $port"
        ufw allow "$port"
    done
    
    # Enable firewall
    echo "y" | ufw enable
    
    log_success "Firewall configured"
}

# =============================================================================
# AMP Installation
# =============================================================================

install_amp_unattended() {
    log_info "Starting AMP unattended installation..."
    
    # Set environment variables for unattended installation
    export USE_ANSWERS=y
    export ANSWER_AMPUSER="$AMP_USERNAME"
    export ANSWER_AMPPASS="$AMP_PASSWORD"
    export ANSWER_SYSPASSWORD="$AMP_SYSTEM_PASSWORD"
    export ANSWER_INSTALLJAVA=y
    export ANSWER_INSTALLSRCDSLIBS=y
    export ANSWER_INSTALLDOCKER=y
    export ANSWER_HTTPS="$ENABLE_HTTPS"
    export ANSWER_EMAIL="$AMP_EMAIL"
    
    if [[ "$ENABLE_HTTPS" == "y" ]] && [[ -n "$DOMAIN_NAME" ]]; then
        export EXT_HOSTNAME="$DOMAIN_NAME"
    fi
    
    # Download and run the AMP installer
    log_info "Downloading and executing AMP installer..."
    bash <(wget -qO- getamp.sh)
    
    log_success "AMP installation completed"
}

# =============================================================================
# Post-Installation Configuration
# =============================================================================

create_backup_script() {
    log_info "Creating automated backup script..."
    
    # Create backup directory
    mkdir -p /home/amp/backups
    
    # Create backup script
    cat > /home/amp/backup.sh <<'EOF'
#!/bin/bash
# AMP Backup Script

BACKUP_DIR="/home/amp/backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Backup AMP data
echo "Starting backup at $(date)"
tar -czf "$BACKUP_DIR/amp_backup_$DATE.tar.gz" /home/amp/.ampdata 2>/dev/null

# Remove old backups
find "$BACKUP_DIR" -name "amp_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: amp_backup_$DATE.tar.gz"
echo "Backup size: $(du -h "$BACKUP_DIR/amp_backup_$DATE.tar.gz" | cut -f1)"
EOF

    chmod +x /home/amp/backup.sh
    chown amp:amp /home/amp/backup.sh
    
    # Add to crontab
    echo "0 3 * * * /home/amp/backup.sh >> /var/log/amp_backup.log 2>&1" | crontab -u amp -
    
    log_success "Backup automation configured"
}

configure_monitoring() {
    log_info "Setting up monitoring..."
    
    # Create monitoring script
    cat > /usr/local/bin/amp-monitor.sh <<'EOF'
#!/bin/bash
# Simple AMP monitoring script

check_service() {
    if systemctl is-active --quiet "ampinstmgr-ADS"; then
        echo "AMP Service: Running"
    else
        echo "AMP Service: STOPPED - Attempting restart..."
        systemctl start ampinstmgr-ADS
    fi
}

check_disk_space() {
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt 90 ]; then
        echo "WARNING: Disk usage is at ${DISK_USAGE}%"
    fi
}

check_memory() {
    MEM_USAGE=$(free | awk 'NR==2 {printf "%.0f", $3/$2 * 100}')
    echo "Memory Usage: ${MEM_USAGE}%"
}

echo "=== AMP Server Health Check - $(date) ==="
check_service
check_disk_space
check_memory
echo "========================================"
EOF

    chmod +x /usr/local/bin/amp-monitor.sh
    
    # Add to crontab for hourly checks
    echo "0 * * * * /usr/local/bin/amp-monitor.sh >> /var/log/amp-monitor.log 2>&1" >> /etc/crontab
    
    log_success "Monitoring configured"
}

# =============================================================================
# Main Installation Function
# =============================================================================

main() {
    log_info "Starting AMP Server Automated Setup"
    echo "====================================="
    
    # Pre-flight checks
    check_root
    check_ubuntu
    
    # Network configuration
    detect_network_interface
    configure_static_ip
    
    # System configuration
    configure_hostname
    configure_lid_behavior
    disable_power_management
    
    # System updates
    update_system
    
    # Security
    configure_firewall
    
    # Install AMP
    install_amp_unattended
    
    # Post-installation
    create_backup_script
    configure_monitoring
    
    # Final message
    echo
    echo "====================================="
    log_success "AMP Server Setup Complete!"
    echo
    echo "Access your AMP panel at:"
    if [[ "$ENABLE_HTTPS" == "y" ]]; then
        echo "  https://$DOMAIN_NAME:8080"
    else
        echo "  http://$STATIC_IP:8080"
    fi
    echo
    echo "Login credentials:"
    echo "  Username: $AMP_USERNAME"
    echo "  Password: $AMP_PASSWORD"
    echo
    echo "SSH access:"
    echo "  ssh $(whoami)@$STATIC_IP"
    echo
    echo "Important paths:"
    echo "  AMP Data: /home/amp/.ampdata"
    echo "  Backups: /home/amp/backups"
    echo "  Logs: /var/log/amp_*.log"
    echo
    log_warning "Please save these credentials in a secure location!"
    echo "====================================="
}

# Run main function
main "$@"