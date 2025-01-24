#!/bin/bash

set -euo pipefail

# Logo
# Credit: figlet font slant by Glenn Chappell
LOGO=$(cat << "EOF"
   __                  __                             __ 
  / /____  ____  _____/ /_____  _____________  ____  / /_
 / __/ _ \/ __ \/ ___/ __/ __ \/ ___/ ___/ _ \/ __ \/ __/
/ /_/  __/ / / (__  ) /_/ /_/ / /  / /  /  __/ / / / /_  
\__/\___/_/ /_/____/\__/\____/_/  /_/   \___/_/ /_/\__/  
EOF
)

# Constants
KMD_VERSION="1.31"

FW_VERSION="80.14.0.0"
FW_FILE="fw_pack-${FW_VERSION}.fwbundle"

SYSTOOLS_VERSION="1.1-5_all"

# Working directory
WORKDIR="/tmp/tenstorrent_install"
# Create if not exist
mkdir -p $WORKDIR
# Clear directory contents
# rm in scripts will never not be scary
# we need the -rf to remove cloned git repos
rm -rf $WORKDIR/*

# Initialize logging
LOG_FILE="${WORKDIR}/install_$(date +%Y%m%d_%H%M%S).log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# log messages; terminal gets color and logfile gets datetime
log() {
    local msg="[INFO] $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

# log errors
error() {
    local msg="[ERROR] $1"
    echo -e "${RED}${msg}${NC}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

# log warnings
warn() {
    local msg="[WARNING] $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

# Check if we have sudo permission
check_has_sudo_perms() {
    if [[ ! -x "/usr/bin/sudo" ]]
    then
        error "Cannot use sudo, exiting..."
        exit 1
    fi
}

# Function to detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID=$ID
        DISTRO_VERSION=$VERSION_ID
    else
        error "Cannot detect Linux distribution"
        exit 1
    fi
}

# Function to verify download
verify_download() {
    local file=$1
    if [ ! -f "$file" ]; then
        error "Download failed: $file not found"
        exit 1
    fi
}

# Function to prompt for yes/no
confirm() {
    while true; do
        read -rp "$1 [Y/n] " yn
        case $yn in
            [Nn]* ) return 1;;
            [Yy]* | "" ) return 0;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Main installation script
main() {
    echo -e "$LOGO"
    echo # newline
    log "Welcome to tenstorrent!"
    log "This script will install drivers and tooling and properly configure your tenstorrent hardware."
    if ! confirm "OK to continue?"; then
        error "Exiting."
        exit 1
    fi
    log "Starting installation"
    log "Log is at $LOG_FILE"

    log "Checking for sudo permissions... (may request password)"
    check_has_sudo_perms	

    # Python package installation preference
    log "How would you like to install Python packages?"
    echo "1. Create a new Python virtual environment (venv) at ~/.tenstorrent-venv"
    echo "2. Use the active virtual environment"
    echo "3. [DEFAULT] Use pipx for isolated package installation"
    read -rp "Enter your choice (1, 2, or 3, or press enter for pipx): " PYTHON_CHOICE

    case $PYTHON_CHOICE in
        1)
            log "Setting up new Python virtual environment"
            python3 -m venv $HOME/.tenstorrent-venv
            source $HOME/.tenstorrent-venv/bin/activate
            warn "You'll need to run \"source $VIRTUAL_ENV/bin/activate\" to use tenstorrent tools."
            PYTHON_INSTALL_CMD="pip install"
            ;;
        2)
            if [ -z "${VIRTUAL_ENV:-}" ]; then
                error "No active virtual environment detected!"
                log "Please activate your virtual environment first and try again"
                exit 1
            fi
            log "Using active virtual environment: $VIRTUAL_ENV"
            warn "You'll need to run \"source $VIRTUAL_ENV/bin/activate\" to use tenstorrent tools."
            PYTHON_INSTALL_CMD="pip install"
            ;;
        *|"3"|"")
            log "Checking for pipx"
            pipx ensurepath
            PYTHON_INSTALL_CMD="pipx install"
            ;;
    esac

    # Check distribution and install base packages
    log "Installing base packages"
    detect_distro
    case $DISTRO_ID in
        "ubuntu"|"debian")
            sudo apt update
            sudo apt install -y wget git python3-pip dkms cargo rustc pipx
            ;;
        "fedora")
            sudo dnf check-update
            sudo dnf install -y wget git python3-pip dkms cargo rust pipx
            ;;
        "rhel"|"centos")
            sudo dnf install -y epel-release
            sudo dnf check-update
            sudo dnf install -y wget git python3-pip dkms cargo rust pipx
            ;;
        *)
            error "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac

    # Install TT-KMD
    log "Installing Kernel-Mode Driver"
    cd $WORKDIR
    git clone https://github.com/tenstorrent/tt-kmd.git
    cd tt-kmd || exit 1
    sudo dkms add .
    sudo dkms install tenstorrent/${KMD_VERSION}
    sudo modprobe tenstorrent

    # Install TT-Flash and Firmware
    log "Installing TT-Flash and updating firmware"
    cd $WORKDIR
    $PYTHON_INSTALL_CMD git+https://github.com/tenstorrent/tt-flash.git

    wget "https://github.com/tenstorrent/tt-firmware/raw/main/${FW_FILE}"
    verify_download "$FW_FILE"

    if ! tt-flash --fw-tar "$FW_FILE"; then
        warn "Initial firmware update failed, attempting force update"
        tt-flash --fw-tar "$FW_FILE" --force
    fi

    # Setup HugePages
    log "Setting up HugePages"
    wget https://github.com/tenstorrent/tt-system-tools/releases/download/upstream%2F1.1/tenstorrent-tools_${SYSTOOLS_VERSION}.deb
    verify_download "tenstorrent-tools_${SYSTOOLS_VERSION}.deb"
    sudo dpkg -i tenstorrent-tools_${SYSTOOLS_VERSION}.deb
    sudo systemctl enable --now tenstorrent-hugepages.service
    sudo systemctl enable --now 'dev-hugepages\x2d1G.mount'

    # Install TT-SMI
    log "Installing System Management Interface"
    $PYTHON_INSTALL_CMD git+https://github.com/tenstorrent/tt-smi

    log "Installation completed successfully!"
    log "Installation log saved to: $LOG_FILE"
    log "Please reboot your system to complete the setup."

    if confirm "Would you like to reboot now?"; then
        sudo reboot
    fi
}

# Start installation
main
