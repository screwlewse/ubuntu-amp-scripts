#!/bin/bash
# =============================================================================
# AMP Quick Setup Script
# Description: Minimal script for quick AMP installation with prompts
# =============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================="
echo "AMP Quick Setup Script"
echo "=================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

# Gather configuration
read -p "Enter AMP admin username [admin]: " AMP_USER
AMP_USER=${AMP_USER:-admin}

read -sp "Enter AMP admin password: " AMP_PASS
echo
read -sp "Confirm AMP admin password: " AMP_PASS_CONFIRM
echo

if [[ "$AMP_PASS" != "$AMP_PASS_CONFIRM" ]]; then
    echo "Passwords do not match!"
    exit 1
fi

read -p "Enter your email (optional, for Let's Encrypt): " EMAIL
read -p "Configure HTTPS? (requires domain name) [y/N]: " HTTPS
HTTPS=${HTTPS:-n}

if [[ "$HTTPS" =~ ^[Yy]$ ]]; then
    read -p "Enter your domain name: " DOMAIN
fi

read -p "Install Java for Minecraft? [Y/n]: " JAVA
JAVA=${JAVA:-y}

echo
echo "=================================="
echo "Configuration Summary:"
echo "  AMP Username: $AMP_USER"
echo "  Email: ${EMAIL:-Not set}"
echo "  HTTPS: $HTTPS"
[[ "$HTTPS" =~ ^[Yy]$ ]] && echo "  Domain: $DOMAIN"
echo "  Install Java: $JAVA"
echo "=================================="
echo

read -p "Continue with installation? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-y}
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 0

# Configure laptop lid behavior
echo -e "${YELLOW}Configuring power management...${NC}"
sed -i 's/#HandleLidSwitch=suspend/HandleLidSwitch=ignore/g' /etc/systemd/logind.conf
systemctl restart systemd-logind.service
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Update system
echo -e "${YELLOW}Updating system...${NC}"
apt-get update && apt-get upgrade -y
apt-get install -y curl wget ufw

# Configure firewall
echo -e "${YELLOW}Configuring firewall...${NC}"
ufw allow 22/tcp
ufw allow 8080/tcp
ufw allow 7777/udp
ufw allow 7778/udp
ufw allow 27015/udp
echo "y" | ufw enable

# Install AMP
echo -e "${YELLOW}Installing AMP...${NC}"
export USE_ANSWERS=y
export ANSWER_AMPUSER="$AMP_USER"
export ANSWER_AMPPASS="$AMP_PASS"
export ANSWER_SYSPASSWORD="$(openssl rand -base64 12)"
export ANSWER_INSTALLJAVA="$JAVA"
export ANSWER_INSTALLSRCDSLIBS=y
export ANSWER_INSTALLDOCKER=y
export ANSWER_HTTPS="$HTTPS"
[[ -n "$EMAIL" ]] && export ANSWER_EMAIL="$EMAIL"
[[ "$HTTPS" =~ ^[Yy]$ ]] && export EXT_HOSTNAME="$DOMAIN"

bash <(wget -qO- getamp.sh)

# Create simple backup script
mkdir -p /home/amp/backups
cat > /home/amp/backup.sh <<'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
tar -czf /home/amp/backups/amp_backup_$DATE.tar.gz /home/amp/.ampdata
find /home/amp/backups -name "amp_backup_*.tar.gz" -mtime +7 -delete
EOF
chmod +x /home/amp/backup.sh
chown amp:amp /home/amp/backup.sh
echo "0 3 * * * /home/amp/backup.sh" | crontab -u amp -

echo
echo -e "${GREEN}=================================="
echo "Installation Complete!"
echo "=================================="
echo
ACCESS_IP=$(hostname -I | awk '{print $1}')

if [[ "$HTTPS" =~ ^[Yy]$ ]]; then
    echo "Access URL: https://$DOMAIN:8080"
else
    echo "Access URL: http://$ACCESS_IP:8080"
fi
echo "Username: $AMP_USER"
echo "Password: [as entered]"
echo
echo "SSH: ssh $(logname)@$ACCESS_IP"
echo
echo "Note: Server is using dynamic IP ($ACCESS_IP)"
echo "IP may change on reboot - check router DHCP list"
echo -e "==================================${NC}"
