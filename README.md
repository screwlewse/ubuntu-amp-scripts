# Complete Game Server Setup Guide
## Ubuntu Server + AMP for ARK Game Server

> **New in v2.0**: This guide now includes automated installation scripts that handle 90% of the setup process automatically!

---

## Quick Start (Automated Installation)

### Option 1: Full Automated Setup
1. Install Ubuntu Server 24.04 LTS (see Part 1 below for details)
2. Download and run the automated setup script:
```bash
# Download the script
wget https://raw.githubusercontent.com/yourusername/amp-setup/main/amp-setup.sh
# OR create it locally by copying from the "AMP Server Automation Scripts" artifact

# Make it executable
chmod +x amp-setup.sh

# Review and edit configuration variables at the top of the script
nano amp-setup.sh

# Run the script
sudo ./amp-setup.sh
```

### Option 2: Interactive Quick Setup
For a simpler interactive installation:
```bash
# Download the quick setup script
wget https://raw.githubusercontent.com/yourusername/amp-setup/main/amp-quick-setup.sh
# OR create it locally by copying from the "Quick Setup Script" artifact

# Run it
sudo bash amp-quick-setup.sh
```

The automated scripts will:
- Configure static IP
- Set up power management for laptops
- Install all prerequisites
- Configure firewall
- Install AMP with your settings
- Set up automated backups
- Create monitoring scripts

---

## Manual Installation Guide

If you prefer manual installation or need to customize specific steps, follow the detailed guide below.

## Part 1: Installing Ubuntu Server

### Download and Create Installation Media
1. Download Ubuntu Server 24.04 LTS from https://ubuntu.com/download/server
2. Create bootable USB using Rufus (Windows) or Balena Etcher (Mac/Linux)
3. Boot your Lenovo laptop from USB (usually F12 or F2 during startup)

### Installation Steps
1. Choose "Install Ubuntu Server"
2. Select your language and keyboard layout
3. Network configuration: Use DHCP (automatic) for now
4. Skip proxy configuration
5. Use default mirror
6. Storage: Use entire disk (guided - use entire disk)
7. Create your user account (remember these credentials!)
8. **IMPORTANT**: Check "Install OpenSSH server" when prompted
9. Skip additional snaps
10. Complete installation and reboot

---

## Automated Installation Details

### What the Full Setup Script Does

The `amp-setup.sh` script automates:

1. **System Configuration**
   - Sets static IP address
   - Configures hostname
   - Disables laptop lid suspend
   - Disables all power management
   - Enables automatic security updates

2. **Prerequisites Installation**
   - Updates system packages
   - Installs required dependencies
   - Configures firewall with UFW
   - Opens necessary ports

3. **AMP Installation**
   - Uses official unattended installation
   - Installs Java for Minecraft
   - Installs 32-bit libraries for Source games
   - Installs Docker support
   - Optionally configures HTTPS

4. **Post-Installation**
   - Creates automated backup scripts
   - Sets up system monitoring
   - Configures log rotation

### Customizing the Automation

Before running the script, edit these variables at the top:

```bash
# AMP Configuration
AMP_USERNAME="admin"              # Your AMP admin username
AMP_PASSWORD="ChangeThisPassword123!"  # Strong password!
AMP_EMAIL="your@email.com"       # For Let's Encrypt certificates

# Network Configuration  
STATIC_IP="192.168.1.100"        # Your desired static IP
GATEWAY_IP="192.168.1.1"         # Your router's IP

# Server Configuration
ENABLE_HTTPS="n"                 # Set to 'y' if you have a domain
DOMAIN_NAME=""                   # Required if HTTPS is enabled

# Game Ports (add more as needed)
GAME_PORTS=(
    "8080/tcp"    # AMP Web Interface
    "7777/udp"    # ARK Game Port
    "7778/udp"    # ARK Query Port
    "27015/udp"   # ARK RCON Port
)
```

### Understanding Unattended Installation

The script uses AMP's official unattended installation feature with these environment variables:

```bash
USE_ANSWERS=y                    # Enable unattended mode
ANSWER_AMPUSER="admin"           # AMP admin username
ANSWER_AMPPASS="password"        # AMP admin password
ANSWER_SYSPASSWORD="syspass"     # Linux amp user password
ANSWER_INSTALLJAVA=y             # Install Java
ANSWER_INSTALLSRCDSLIBS=y        # Install 32-bit libraries
ANSWER_INSTALLDOCKER=y           # Install Docker
ANSWER_HTTPS=n                   # Configure HTTPS
```

---

### First Login and Updates
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y curl wget nano htop net-tools software-properties-common apt-transport-https ca-certificates gnupg lsb-release
```

### Set Static IP Address (Recommended)
First, find your network interface name:
```bash
ip a
```

Edit netplan configuration:
```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

Replace contents with (adjust for your network):
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:  # Replace with your interface name
      dhcp4: no
      addresses:
        - 192.168.1.100/24  # Choose an IP in your network range
      gateway4: 192.168.1.1    # Your router's IP
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
```

Apply the configuration:
```bash
sudo netplan apply
```

---

## Part 3: Configure Laptop for Server Use

### Prevent Sleep When Lid Closed
Edit logind configuration:
```bash
sudo nano /etc/systemd/logind.conf
```

Find and uncomment/change these lines:
```
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

Restart the service:
```bash
sudo systemctl restart systemd-logind.service
```

### Disable Screen Blanking and Power Management
```bash
# Disable screen blanking
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Set power profile to performance
sudo apt install -y linux-tools-common linux-tools-generic
sudo cpupower frequency-set -g performance
```

### Configure Automatic Security Updates
```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
# Select "Yes" when prompted
```

---

## Part 4: Install AMP (Application Management Panel)

### Add CubeCoders Repository
```bash
# Add repository key
sudo apt-key adv --fetch-keys http://repo.cubecoders.com/archive.key

# Add repository
sudo apt-add-repository "deb http://repo.cubecoders.com/ debian/"

# Update package list
sudo apt update
```

### Install AMP
```bash
# Install AMP
sudo apt install -y ampinstmgr

# Create AMP user (recommended for security)
sudo useradd -d /home/amp -m amp -s /bin/bash
sudo passwd amp  # Set a password for the amp user
```

### Setup AMP Instance
```bash
# Switch to root for initial setup
sudo su -

# Create the main AMP instance (ADS - Application Deployment Service)
ampinstmgr install ADS --username amp --password YOURPASSWORD --email your@email.com +Core.Login.Username "admin"

# Note: Replace YOURPASSWORD with a strong password for the AMP web interface
# This will be your login for the web panel
```

### Configure Firewall
```bash
# Install UFW (Uncomplicated Firewall)
sudo apt install -y ufw

# Allow SSH
sudo ufw allow 22/tcp

# Allow AMP web interface
sudo ufw allow 8080/tcp

# Allow ARK game ports (adjust if using different ports)
sudo ufw allow 7777/udp
sudo ufw allow 7778/udp
sudo ufw allow 27015/udp

# Enable firewall
sudo ufw enable
```

### Start AMP
```bash
# Start AMP service
sudo systemctl enable ampinstmgr-ADS
sudo systemctl start ampinstmgr-ADS

# Check status
sudo systemctl status ampinstmgr-ADS
```

---

## Part 5: Access AMP Web Interface

### Finding Your Server's IP
```bash
# Show IP address
ip addr show | grep "inet " | grep -v 127.0.0.1
```

### Accessing AMP
1. Open a web browser on any computer on your local network
2. Navigate to: `http://YOUR_SERVER_IP:8080`
3. Login with:
   - Username: `admin`
   - Password: The password you set during AMP installation

### First Time AMP Setup
1. **Activate License**: Enter your AMP license key
2. **Create New Instance**: 
   - Click "Create Instance"
   - Select "ARK: Survival Evolved"
   - Choose installation directory
   - Set instance name
3. **Configure ARK Server**:
   - Set server name
   - Set passwords
   - Configure game settings
   - Install mods if desired

---

## Part 6: Remote Access Setup

### SSH Access from Windows
Install Windows Terminal and use:
```powershell
ssh username@YOUR_SERVER_IP
```

### SSH Access from Mac/Linux
```bash
ssh username@YOUR_SERVER_IP
```

### Optional: Change SSH Port for Security
```bash
sudo nano /etc/ssh/sshd_config
# Find "Port 22" and change to something like "Port 2222"

sudo systemctl restart ssh
sudo ufw allow 2222/tcp
sudo ufw delete allow 22/tcp
```

---

## Part 7: Backup Configuration

### Automatic AMP Backups
In AMP web interface:
1. Go to your ARK instance
2. Click "Configuration" → "Backups"
3. Enable automatic backups
4. Set schedule and retention

### System-Level Backup Script
Create backup script:
```bash
sudo nano /home/amp/backup.sh
```

Add content:
```bash
#!/bin/bash
# Backup script for ARK server

BACKUP_DIR="/home/amp/backups"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup AMP data
tar -czf $BACKUP_DIR/amp_backup_$DATE.tar.gz /home/amp/.ampdata

# Keep only last 7 days of backups
find $BACKUP_DIR -name "amp_backup_*.tar.gz" -mtime +7 -delete

echo "Backup completed: amp_backup_$DATE.tar.gz"
```

Make executable and schedule:
```bash
# Make executable
sudo chmod +x /home/amp/backup.sh

# Add to crontab (daily at 3 AM)
sudo crontab -e
# Add this line:
0 3 * * * /home/amp/backup.sh >> /var/log/amp_backup.log 2>&1
```

---

## Part 8: Monitoring and Maintenance

### Install Monitoring Tools
```bash
# Install Webmin for general system management (optional)
wget -q -O- http://www.webmin.com/jcameron-key.asc | sudo apt-key add -
sudo sh -c 'echo "deb http://download.webmin.com/download/repository sarge contrib" > /etc/apt/sources.list.d/webmin.list'
sudo apt update
sudo apt install -y webmin

# Allow Webmin through firewall
sudo ufw allow 10000/tcp
```

### Useful Commands
```bash
# Check system resources
htop

# Check disk space
df -h

# Check AMP logs
sudo journalctl -u ampinstmgr-ADS -f

# Restart AMP
sudo systemctl restart ampinstmgr-ADS

# Check network connections
sudo netstat -tulpn

# View system logs
sudo tail -f /var/log/syslog
```

---

## Part 9: Troubleshooting

### Common Issues and Solutions

**Can't access web interface:**
```bash
# Check if AMP is running
sudo systemctl status ampinstmgr-ADS

# Check firewall
sudo ufw status

# Check if port is listening
sudo netstat -tulpn | grep 8080
```

**ARK server won't start:**
- Check RAM usage (ARK needs 6-8GB minimum)
- Verify ports aren't in use
- Check AMP logs in web interface

**Laptop shuts down despite lid settings:**
```bash
# Double-check settings
cat /etc/systemd/logind.conf | grep HandleLid

# Disable all power management
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

---

## Quick Reference

### Server Access
- **AMP Web Panel**: http://YOUR_SERVER_IP:8080
- **Webmin** (if installed): https://YOUR_SERVER_IP:10000
- **SSH**: ssh username@YOUR_SERVER_IP

### Important Paths
- **AMP Data**: `/home/amp/.ampdata`
- **ARK Server Files**: `/home/amp/.ampdata/instances/INSTANCENAME/`
- **Logs**: `/var/log/`

### Emergency Commands
```bash
# Restart everything
sudo reboot

# Stop ARK via command line
sudo su - amp -c "ampinstmgr stop INSTANCENAME"

# Start ARK via command line
sudo su - amp -c "ampinstmgr start INSTANCENAME"

# Full system update
sudo apt update && sudo apt upgrade -y
```

---

## Security Recommendations

1. **Change default passwords** for all accounts
2. **Enable UFW firewall** (already done above)
3. **Keep system updated** with automatic security updates
4. **Regular backups** (automated above)
5. **Monitor logs** for suspicious activity
6. Consider using **Fail2ban** for SSH protection:
```bash
sudo apt install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

---

## Next Steps

1. Access AMP web interface
2. Enter your license key
3. Create ARK instance
4. Configure your server settings
5. Start the server
6. Connect from ARK game client using: YOUR_SERVER_IP:7777

**Congratulations! Your ARK server is ready to use!**
