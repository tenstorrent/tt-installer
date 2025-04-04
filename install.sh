#!/bin/bash
# SPDX-FileCopyrightText: © 2025 Tenstorrent AI ULC
# SPDX-License-Identifier: Apache-2.0

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

# Fetch latest kmd from git tags
TT_KMD_GIT_URL="https://github.com/tenstorrent/tt-kmd.git"
fetch_latest_kmd_version() {
	local latest_kmd=$(git ls-remote --tags --refs "${TT_KMD_GIT_URL}" | awk -F/ '{print $NF}' | sort -V | tail -n1)
	echo "${latest_kmd#ttkmd-}"
}

# Fetch lastest FW version
TT_FW_GIT_URL="https://github.com/tenstorrent/tt-firmware.git"
fetch_latest_fw_version() {
	local latest_fw=$(git ls-remote --tags --refs "${TT_FW_GIT_URL}" | awk -F/ '{print $NF}' | sort -V | tail -n1)
	echo "${latest_fw#v}" # Remove 'v' prefix if present
}

# Fetch latest systools version
# Currently unused due to systools tags being broken
TT_SYSTOOLS_GIT_URL="https://github.com/tenstorrent/tt-system-tools.git"
fetch_latest_systools_version() {
	local latest_systools=$(git ls-remote --tags --refs "${TT_SYSTOOLS_GIT_URL}" | awk -F/ '{print $NF}' | sort -V | tail -n1)
	echo "${latest_systools#v}" # Remove 'upstream/' prefix
}

# Non-interactive mode flag (set to 0 to enable)
NON_INTERACTIVE=${TT_NON_INTERACTIVE:-1}

# Skip KMD installation flag (set to 0 to skip)
SKIP_INSTALL_KMD=${TT_SKIP_INSTALL_KMD:-1}

# Skip HugePages installation flag (set to 0 to skip)
SKIP_INSTALL_HUGEPAGES=${TT_SKIP_INSTALL_HUGEPAGES:-1}

# Skip tt-flash and firmware update flag (set to 0 to skip)
SKIP_UPDATE_FIRMWARE=${TT_SKIP_UPDATE_FIRMWARE:-1}

# Container mode flag (set to 0 to enable, which skips KMD and HugePages)
CONTAINER_MODE=${TT_CONTAINER_MODE:-1}
# If container mode is enabled, skip KMD and HugePages
if [[ "${CONTAINER_MODE}" = "0" ]]; then
    SKIP_INSTALL_KMD=0
    SKIP_INSTALL_HUGEPAGES=0
fi

# Optional assignment- uses TT_ envvar version if present, otherwise latest
KMD_VERSION="${TT_KMD_VERSION:-$(fetch_latest_kmd_version)}"
FW_VERSION="${TT_FW_VERSION:-$(fetch_latest_fw_version)}"
SYSTOOLS_VERSION="${TT_SYSTOOLS_VERSION:-$(fetch_latest_systools_version)}"

# Set default Python installation choice
# 1 = Use active venv, 2 = Create new venv, 3 = Use pipx, 4 = system level (not recommended)
PYTHON_CHOICE="${TT_PYTHON_CHOICE:-2}"
declare -A PYTHON_CHOICE_TXT
PYTHON_CHOICE_TXT[1]="Existing venv"
PYTHON_CHOICE_TXT[2]="New venv"
PYTHON_CHOICE_TXT[3]="pipx"
PYTHON_CHOICE_TXT[4]="System Python"

# Option to automatically reboot after installation
AUTO_REBOOT="${TT_AUTO_REBOOT:-1}"

# Update FW_FILE based on FW_VERSION
FW_FILE="fw_pack-${FW_VERSION}.fwbundle"

# Create working directory
TMP_DIR_TEMPLATE="tenstorrent_install_XXXXXX"
# Use mktemp to get a temporary directory
WORKDIR=$(mktemp -d -p /tmp "${TMP_DIR_TEMPLATE}")

# Initialize logging
LOG_FILE="${WORKDIR}/install.log"
# Redirect stdout to the logfile.
# Removes color codes and prepends the date
exec > >( \
		tee >( \
				stdbuf -o0 \
						sed 's/\x1B\[[0-9;]*[A-Za-z]//g' | \
						xargs -d '\n' -I {} date '+[%F %T] {}' \
				> "${LOG_FILE}" \
				) \
		)
exec 2>&1

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# log messages to terminal (with color)
log() {
	local msg="[INFO] $1"
	echo -e "${GREEN}${msg}${NC}"  # Color output to terminal
}

# log errors
error() {
	local msg="[ERROR] $1"
	echo -e "${RED}${msg}${NC}"
}

# log warnings
warn() {
	local msg="[WARNING] $1"
	echo -e "${YELLOW}${msg}${NC}"
}

check_has_sudo_perms() {
	if ! sudo true; then
		error "Cannot use sudo, exiting..."
		exit 1
	fi
}

detect_distro() {
	if [[ -f /etc/os-release ]]; then
		. /etc/os-release
		DISTRO_ID=${ID}
		DISTRO_VERSION=${VERSION_ID}
		check_is_ubuntu_20
	else
		error "Cannot detect Linux distribution"
		exit 1
	fi
}

check_is_ubuntu_20() {
	# Check if it's Ubuntu and version starts with 20
	if [[ "${DISTRO_ID}" = "ubuntu" ]] && [[ "${DISTRO_VERSION}" == 20* ]]; then
		IS_UBUNTU_20=0 # Ubuntu 20.xx
	else
		IS_UBUNTU_20=1 # Not that
	fi
}

# Function to verify download
verify_download() {
	local file=$1
	if [[ ! -f "${file}" ]]; then
		error "Download failed: ${file} not found"
		exit 1
	fi
}

# Function to prompt for yes/no
confirm() {
	# In non-interactive mode, always return true
	if [[ "${NON_INTERACTIVE}" = "0" ]]; then
		return 0
	fi

	while true; do
		read -rp "$1 [Y/n] " yn
		case ${yn} in
			[Nn]* ) echo && return 1;;
			[Yy]* | "" ) echo && return 0;;
			* ) echo "Please answer yes or no.";;
		esac
	done
}

# Get Python installation choice interactively or use default
get_python_choice() {
	# If TT_PYTHON_CHOICE is set via environment variable, use that
	if [[ -n "${TT_PYTHON_CHOICE+x}" ]]; then
		log "Using Python installation method from environment variable (option $PYTHON_CHOICE: ${PYTHON_CHOICE_TXT[${PYTHON_CHOICE}]})"
		return
	# Otherwise, if in non-interactive mode, use the default
	elif [[ "${NON_INTERACTIVE}" = "0" ]]; then
			log "Non-interactive mode, using default Python installation method (option $PYTHON_CHOICE: ${PYTHON_CHOICE_TXT[${PYTHON_CHOICE}]})"
			return
	fi

	# Interactive mode with no TT_PYTHON_CHOICE set
	log "How would you like to install Python packages?"
	echo "1. Use the active virtual environment"
	echo "2. [DEFAULT] Create a new Python virtual environment (venv) at ${NEW_VENV_LOCATION}"
	# The pipx version on ubuntu 20 is too old to install git packages. They must use a venv
	echo "3. Use the system pathing, available for multiple users. *** NOT RECOMMENDED UNLESS YOU ARE SURE ***"
	if [[ "${IS_UBUNTU_20}" != "0" ]]; then
		echo "4. Use pipx for isolated package installation"
	fi
	read -rp "Enter your choice (1, 2...) or press enter for default: " user_choice
	echo # newline

	# If user provided a value, update PYTHON_CHOICE
	if [[ -n "${user_choice}" ]]; then
		PYTHON_CHOICE=${user_choice}
	fi
}

get_new_venv_location() {
    # If user provides path, use it
	if [[ -v TT_NEW_VENV_LOCATION ]]; then
		NEW_VENV_LOCATION="${TT_NEW_VENV_LOCATION}"
	# If XDG_DATA_HOME is defined, use that
	elif [[ -v XDG_DATA_HOME ]]; then
		NEW_VENV_LOCATION="${XDG_DATA_HOME}/tenstorrent-venv"
	# Fallback to ${HOME}/.tenstorrent-venv
	else
		NEW_VENV_LOCATION="${HOME}/.tenstorrent-venv"
	fi
}

# Main installation script
main() {
	echo -e "${LOGO}"
	echo # newline
	log "Welcome to tenstorrent!"
	log "Log is at ${LOG_FILE}"

	log "This script will install drivers and tooling and properly configure your tenstorrent hardware."
	if ! confirm "OK to continue?"; then
		error "Exiting."
		exit 1
	fi
	log "Starting installation"
	log "Using software versions:"
	log "  KMD: ${KMD_VERSION}"
	log "  Firmware: ${FW_VERSION}"
	log "  System Tools: ${SYSTOOLS_VERSION}"

	# Log special mode settings
	if [[ "${NON_INTERACTIVE}" = "0" ]]; then
		warn "Running in non-interactive mode"
	fi
	if [[ "${CONTAINER_MODE}" = "0" ]]; then
		warn "Running in container mode"
	fi
	if [[ "${SKIP_INSTALL_KMD}" = "0" ]]; then
		warn "KMD installation will be skipped"
	fi
	if [[ "${SKIP_INSTALL_HUGEPAGES}" = "0" ]]; then
		warn "HugePages setup will be skipped"
	fi
	if [[ "${SKIP_UPDATE_FIRMWARE}" = "0" ]]; then
		warn "TT-Flash and firmware update will be skipped"
	fi

	log "Checking for sudo permissions... (may request password)"
	check_has_sudo_perms

	# Check distribution and install base packages
	detect_distro
	log "Installing base packages"
	case "${DISTRO_ID}" in
		"ubuntu"|"debian")
			sudo apt update
			# The pipx version on ubuntu 20 is too old to install git packages. It's not needed.
			if [[ "${IS_UBUNTU_20}" != "0" ]]; then
				sudo apt install -y wget git python3-pip dkms cargo rustc pipx
			else
				sudo apt install -y wget git python3-pip dkms cargo rustc
			fi
			;;
		"fedora")
			sudo dnf install -y wget git python3-pip python3-devel dkms cargo rust pipx
			;;
		"rhel"|"centos")
			sudo dnf install -y epel-release
			sudo dnf install -y wget git python3-pip python3-devel dkms cargo rust pipx
			;;
		*)
			error "Unsupported distribution: ${DISTRO_ID}"
			exit 1
			;;
	esac

	if [[ "${IS_UBUNTU_20}" = "0" ]]; then
		warn "Ubuntu 20 is deprecated and support will be removed in a future release!"
	fi

	# Python package installation preference
	get_new_venv_location
	get_python_choice

	# Enforce restrictions on Ubuntu 20
	if [[ "${IS_UBUNTU_20}" = "0" && "${PYTHON_CHOICE}" = "4" ]]; then
		warn "pipx installation not supported on Ubuntu 20, defaulting to virtual environment"
		PYTHON_CHOICE=2
	fi

	# Set up Python environment based on choice
	case ${PYTHON_CHOICE} in
		1)
			if [[ -z "${VIRTUAL_ENV:-}" ]]; then
				error "No active virtual environment detected!"
				error "Please activate your virtual environment first and try again"
				exit 1
			fi
			log "Using active virtual environment: ${VIRTUAL_ENV}"
			INSTALLED_IN_VENV=0
			PYTHON_INSTALL_CMD="pip install"
			;;
		3)
			log "Using system pathing"
			INSTALLED_IN_VENV=0
			# If we're on a modern OS, specify we want to break sys packages
			if [[ "${IS_UBUNTU_20}" != "0" ]]; then
				PYTHON_INSTALL_CMD="pip install --break-system-packages"
			else
				PYTHON_INSTALL_CMD="pip install"
			fi
			;;
		4)
			log "Using pipx for isolated package installation"
			pipx ensurepath
			INSTALLED_IN_VENV=1
			PYTHON_INSTALL_CMD="pipx install"
			;;
		*|"2")
			log "Setting up new Python virtual environment"
			python3 -m venv "${NEW_VENV_LOCATION}"
			source "${NEW_VENV_LOCATION}/bin/activate"
			INSTALLED_IN_VENV=0
			PYTHON_INSTALL_CMD="pip install"
			;;
	esac

	# Install TT-KMD
	# Skip KMD installation if flag is set
	if [[ "${SKIP_INSTALL_KMD}" = "0" ]]; then
		log "Skipping KMD installation"
	else
		log "Installing Kernel-Mode Driver"
		cd "${WORKDIR}"
		# Get the KMD version, if installed, while silencing errors
		if KMD_INSTALLED_VERSION=$(modinfo -F version tenstorrent 2>/dev/null); then
			warn "Found active KMD module, version ${KMD_INSTALLED_VERSION}."
			if confirm "Force KMD reinstall?"; then
				sudo dkms remove "tenstorrent/${KMD_INSTALLED_VERSION}"
				git clone --branch "ttkmd-${KMD_VERSION}" https://github.com/tenstorrent/tt-kmd.git
				sudo dkms add tt-kmd
				sudo dkms install "tenstorrent/${KMD_VERSION}"
				sudo modprobe tenstorrent
			else
				warn "Skipping KMD installation"
			fi
		else
			# Only install KMD if it's not already installed
			git clone --branch "ttkmd-${KMD_VERSION}" https://github.com/tenstorrent/tt-kmd.git
			sudo dkms add tt-kmd
			sudo dkms install "tenstorrent/${KMD_VERSION}"
			sudo modprobe tenstorrent
		fi
	fi

	# Install TT-Flash and Firmware
	# Skip tt-flash installation if flag is set
	if [[ "${SKIP_UPDATE_FIRMWARE}" = "0" ]]; then
		log "Skipping TT-Flash and firmware update installation"
	else
		log "Installing TT-Flash and updating firmware"
		cd "${WORKDIR}"
		${PYTHON_INSTALL_CMD} git+https://github.com/tenstorrent/tt-flash.git

		wget "https://github.com/tenstorrent/tt-firmware/raw/main/${FW_FILE}"
		verify_download "${FW_FILE}"

		if ! tt-flash --fw-tar "${FW_FILE}"; then
			warn "Initial firmware update failed, attempting force update"
			tt-flash --fw-tar "${FW_FILE}" --force
		fi
	fi

	# Setup HugePages
	BASE_TOOLS_URL="https://github.com/tenstorrent/tt-system-tools/releases/download/upstream"
	# Skip HugePages installation if flag is set
	if [[ "${SKIP_INSTALL_HUGEPAGES}" = "0" ]]; then
		warn "Skipping HugePages setup"
	else
		log "Setting up HugePages"
		case "${DISTRO_ID}" in
			"ubuntu"|"debian")
				TOOLS_FILENAME="tenstorrent-tools_${SYSTOOLS_VERSION}-1_all.deb"
				TOOLS_URL="${BASE_TOOLS_URL}/v${SYSTOOLS_VERSION}/${TOOLS_FILENAME}"
				wget "${TOOLS_URL}"
				verify_download "${TOOLS_FILENAME}"
				sudo dpkg -i "${TOOLS_FILENAME}"
				sudo systemctl enable --now tenstorrent-hugepages.service
				sudo systemctl enable --now 'dev-hugepages\x2d1G.mount'
				;;
			"fedora"|"rhel"|"centos")
				TOOLS_FILENAME="tenstorrent-tools-${SYSTOOLS_VERSION}-1.noarch.rpm"
				TOOLS_URL="${BASE_TOOLS_URL}/v${SYSTOOLS_VERSION}/${TOOLS_FILENAME}"
				wget "${TOOLS_URL}"
				verify_download "${TOOLS_FILENAME}"
				sudo dnf install -y "${TOOLS_FILENAME}"
				sudo systemctl enable --now tenstorrent-hugepages.service
				sudo systemctl enable --now 'dev-hugepages\x2d1G.mount'
				;;
			*)
				error "This distro is unsupported. Skipping HugePages install!"
				;;
		esac
	fi

	# Install TT-SMI
	log "Installing System Management Interface"
	${PYTHON_INSTALL_CMD} git+https://github.com/tenstorrent/tt-smi

	log "Installation completed successfully!"
	log "Installation log saved to: ${LOG_FILE}"
	if [[ "${INSTALLED_IN_VENV}" = "0" ]]; then
		warn "You'll need to run \"source ${VIRTUAL_ENV}/bin/activate\" to use tenstorrent tools."
	fi
	log "Please reboot your system to complete the setup."
	log "After rebooting, try running 'tt-smi' to see the status of your hardware."

	# Auto-reboot if specified
	if [[ "${AUTO_REBOOT}" = "0" ]]; then
		log "Auto-reboot enabled. Rebooting now..."
		sudo reboot
	fi
	# Otherwise, ask if in interactive mode
	if [[ "${NON_INTERACTIVE}" = 1 ]]; then
		if confirm "Would you like to reboot now?"; then
			log "Rebooting..."
			sudo reboot
		fi
	fi
}

# Start installation
main

# Don't muck with this unless you know what you are doing -warthog9
# vim: noai:ts=4:sw=4
