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

# ========================= GIT URLs =========================

# Fetch latest kmd from git tags
TT_KMD_GH_REPO="tenstorrent/tt-kmd"
fetch_latest_kmd_version() {
	if ! command -v jq &> /dev/null; then
		exit
	fi
	local latest_kmd
	latest_kmd=$(wget -qO- https://api.github.com/repos/"${TT_KMD_GH_REPO}"/releases/latest | jq -r '.tag_name')
	echo "${latest_kmd#ttkmd-}"
}

# Fetch lastest FW version
TT_FW_GH_REPO="tenstorrent/tt-firmware"
fetch_latest_fw_version() {
	if ! command -v jq &> /dev/null; then
		exit
	fi
	local latest_fw
	latest_fw=$(wget -qO- https://api.github.com/repos/"${TT_FW_GH_REPO}"/releases/latest | jq -r '.tag_name')
	echo "${latest_fw#v}" # Remove 'v' prefix if present
}

# Fetch latest systools version
TT_SYSTOOLS_GH_REPO="tenstorrent/tt-system-tools"
fetch_latest_systools_version() {
	if ! command -v jq &> /dev/null; then
		exit
	fi
	local latest_systools
	latest_systools=$(wget -qO- https://api.github.com/repos/"${TT_SYSTOOLS_GH_REPO}"/releases/latest | jq -r '.tag_name')
	echo "${latest_systools#v}" # Remove 'v' prefix if present
}

# Fetch latest tt-smi version
TT_SMI_GH_REPO="tenstorrent/tt-smi"
fetch_latest_smi_version() {
	if ! command -v jq &> /dev/null; then
		exit
	fi
	local latest_smi
	latest_smi=$(wget -qO- https://api.github.com/repos/"${TT_SMI_GH_REPO}"/releases/latest | jq -r '.tag_name')
	echo "${latest_smi}"
}

# Fetch latest tt-flash version
TT_FLASH_GH_REPO="tenstorrent/tt-flash"
fetch_latest_flash_version() {
	if ! command -v jq &> /dev/null; then
		exit
	fi
	local latest_flash
	latest_flash=$(wget -qO- https://api.github.com/repos/"${TT_FLASH_GH_REPO}"/releases/latest | jq -r '.tag_name')
	echo "${latest_flash}"
}

# ========================= Podman Metalium Settings =========================

# Podman Metalium URLs and Settings
METALIUM_IMAGE_URL="${TT_METALIUM_IMAGE_URL:-ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-release-amd64}"
METALIUM_IMAGE_TAG="${TT_METALIUM_IMAGE_TAG:-latest-rc}"
PODMAN_METALIUM_SCRIPT_DIR="${HOME}/.local/bin"
PODMAN_METALIUM_SCRIPT_NAME="tt-metalium"

# ========================= Boolean Parameters =========================

# Skip KMD installation flag (set to 0 to skip)
SKIP_INSTALL_KMD=${TT_SKIP_INSTALL_KMD:-1}

# Skip HugePages installation flag (set to 0 to skip)
SKIP_INSTALL_HUGEPAGES=${TT_SKIP_INSTALL_HUGEPAGES:-1}

# Skip tt-flash and firmware update flag (set to 0 to skip)
SKIP_UPDATE_FIRMWARE=${TT_SKIP_UPDATE_FIRMWARE:-1}

# Skip Podman installation flag (set to 0 to skip)
SKIP_INSTALL_PODMAN=${TT_SKIP_INSTALL_PODMAN:-1}

# Skip Podman Metalium installation flag (set to 0 to skip)
SKIP_INSTALL_METALIUM_CONTAINER=${TT_SKIP_INSTALL_METALIUM_CONTAINER:-1}

# ========================= String Parameters =========================

# Set default Python installation choice
# 1 = Use active venv, 2 = Create new venv, 3 = Use pipx, 4 = system level (not recommended)
PYTHON_CHOICE="${TT_PYTHON_CHOICE:-2}"
declare -A PYTHON_CHOICE_TXT
PYTHON_CHOICE_TXT[1]="Existing venv"
PYTHON_CHOICE_TXT[2]="New venv"
PYTHON_CHOICE_TXT[3]="System Python"
PYTHON_CHOICE_TXT[4]="pipx"

# Post-install reboot behavior
# 1 = Ask the user, 2 = never, 3 = always
REBOOT_OPTION="${TT_REBOOT_OPTION:-1}"
declare -A REBOOT_OPTION_TXT
REBOOT_OPTION_TXT[1]="Ask the user"
REBOOT_OPTION_TXT[2]="Never reboot"
# shellcheck disable=SC2034  # REBOOT_OPTION_TXT is currently unused but it's good docs
REBOOT_OPTION_TXT[3]="Always reboot"

# ========================= Modes =========================

# Container mode flag (set to 0 to enable, which skips KMD and HugePages and never reboots)
CONTAINER_MODE=${TT_MODE_CONTAINER:-1}
# If container mode is enabled, skip KMD and HugePages
if [[ "${CONTAINER_MODE}" = "0" ]]; then
	SKIP_INSTALL_KMD=0
	SKIP_INSTALL_HUGEPAGES=0 # Both KMD and HugePages must live on the host kernel
	SKIP_INSTALL_PODMAN=0 # No podman in podman
	REBOOT_OPTION=2 # Do not reboot
fi

# Non-interactive mode flag (set to 0 to enable)
NON_INTERACTIVE_MODE=${TT_MODE_NON_INTERACTIVE:-1}
if [[ "${NON_INTERACTIVE_MODE}" = "0" ]]; then
	# In non-interactive mode, we can't ask the user for anything
	# So if they don't provide a reboot choice we will pick a default
	if [[ "${REBOOT_OPTION}" = "1" ]]; then
		REBOOT_OPTION=2 # Do not reboot
	fi
fi

# ========================= Main Script =========================

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

# log an error and then exit
error_exit() {
    error "$1"
    exit 1
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
	# shellcheck disable=SC1091 # Always present
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
	if [[ "${NON_INTERACTIVE_MODE}" = "0" ]]; then
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
		log "Using Python installation method from environment variable (option ${PYTHON_CHOICE}: ${PYTHON_CHOICE_TXT[${PYTHON_CHOICE}]})"
		return
	# Otherwise, if in non-interactive mode, use the default
	elif [[ "${NON_INTERACTIVE_MODE}" = "0" ]]; then
			log "Non-interactive mode, using default Python installation method (option ${PYTHON_CHOICE}: ${PYTHON_CHOICE_TXT[${PYTHON_CHOICE}]})"
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

fetch_tt_sw_versions() {
	# Use TT_ envvar version if present, otherwise latest
	KMD_VERSION="${TT_KMD_VERSION:-$(fetch_latest_kmd_version)}"
	FW_VERSION="${TT_FW_VERSION:-$(fetch_latest_fw_version)}"
	SYSTOOLS_VERSION="${TT_SYSTOOLS_VERSION:-$(fetch_latest_systools_version)}"
	SMI_VERSION="${TT_SMI_VERSION:-$(fetch_latest_smi_version)}"
	FLASH_VERSION="${TT_FLASH_VERSION:-$(fetch_latest_flash_version)}"

	# If the user provides nothing and the functions fail to execute, take note of that,
	# we will retry later
	if [[ 
		${KMD_VERSION} != "" &&\
		${FW_VERSION} != "" &&\
		${SYSTOOLS_VERSION} != "" &&\
		${SMI_VERSION} != "" &&\
		${FLASH_VERSION} != ""
	]]; then
		HAVE_SET_TT_SW_VERSIONS=0 # True
		log "Using software versions:"
		log "  TT-KMD: ${KMD_VERSION}"
		log "  Firmware: ${FW_VERSION}"
		log "  System Tools: ${SYSTOOLS_VERSION}"
		log "  tt-smi: ${SMI_VERSION#v}"
		log "  tt-flash: ${FLASH_VERSION#v}"
	else
		HAVE_SET_TT_SW_VERSIONS=1
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

# Function to check if Podman is installed
check_podman_installed() {
	if command -v podman &> /dev/null; then
		log "Podman is already installed"
	else
		log "Podman is not installed"
		return 1
	fi
}

# Function to install Podman
install_podman() {
	log "Installing Podman"
	cd "${WORKDIR}"

	# Add GUIDs/UIDs for rootless Podman
	# See https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md
	sudo usermod --add-subgids 10000-75535 "$(whoami)"
	sudo usermod --add-subuids 10000-75535 "$(whoami)"

	# Install Podman using package manager
	case "${DISTRO_ID}" in
		"ubuntu"|"debian")
			sudo apt install -y podman
			;;
		"fedora")
			sudo dnf install -y podman
			;;
		"rhel"|"centos")
			sudo dnf install -y podman
			;;
		*)
			error "Unsupported distribution for Podman installation: ${DISTRO_ID}"
			return 1
			;;
	esac

	# Verify Podman installation
	if podman --version; then
		log "Podman installed successfully"
	else
		error "Podman installation failed"
		return 1
	fi

	return 0
}

# Install Podman Metalium container
install_podman_metalium() {
	log "Installing Metalium via Podman"

	# Create wrapper script directory
	mkdir -p "${PODMAN_METALIUM_SCRIPT_DIR}" || error_exit "Failed to create script directory"

	# Create wrapper script
	log "Creating wrapper script..."
	cat > "${PODMAN_METALIUM_SCRIPT_DIR}/${PODMAN_METALIUM_SCRIPT_NAME}" << EOF
#!/bin/bash
# Wrapper script for tt-metalium using Podman

# Image configuration
METALIUM_IMAGE="${METALIUM_IMAGE_URL}:${METALIUM_IMAGE_TAG}"

# Run the command using Podman
podman run --rm -it \\
  --volume=/dev/hugepages-1G:/dev/hugepages-1G \\
  --volume=\${HOME}:/home/user \\
  --device=/dev/tenstorrent:/dev/tenstorrent \\
  --workdir=/home/user \\
  --env=DISPLAY=\${DISPLAY} \\
  --env=HOME=/home/user \\
  --env=TERM=\${TERM:-xterm-256color} \\
  --network=host \\
  --security-opt label=disable \\
  \${METALIUM_IMAGE} "\$@"
EOF

	# Make the script executable
	chmod +x "${PODMAN_METALIUM_SCRIPT_DIR}/${PODMAN_METALIUM_SCRIPT_NAME}" || error_exit "Failed to make script executable"

	# Check if the directory is in PATH
	if [[ ":${PATH}:" != *":${PODMAN_METALIUM_SCRIPT_DIR}:"* ]]; then
		warn "${PODMAN_METALIUM_SCRIPT_DIR} is not in your PATH."
		warn "A restart may fix this, or you may need to update your shell RC"
	fi

	# Pull the image
	log "Pulling the tt-metalium image (this may take a while)..."
	podman pull "${METALIUM_IMAGE_URL}:${METALIUM_IMAGE_TAG}" || error "Failed to pull image"

	log "Metalium installation completed"
	return 0
}

get_podman_metalium_choice() {
	# If we're on Ubuntu 20, Podman is not available - force skip regardless of environment variable
	if [[ "${IS_UBUNTU_20}" = "0" ]]; then
		SKIP_INSTALL_METALIUM_CONTAINER=0
		SKIP_INSTALL_PODMAN=0
		return
	fi

	# If TT_SKIP_INSTALL_METALIUM_CONTAINER is set via environment variable, use that
	if [[ -n "${TT_SKIP_INSTALL_METALIUM_CONTAINER+x}" ]]; then
		log "Using Podman Metalium installation preference from environment variable (got ${SKIP_INSTALL_METALIUM_CONTAINER})"
		return
	# Otherwise, if in non-interactive mode, use the default
	elif [[ "${NON_INTERACTIVE_MODE}" = "0" ]]; then
		log "Non-interactive mode, using default Podman Metalium installation preference (got ${SKIP_INSTALL_METALIUM_CONTAINER})"
		return
	fi

	# Only ask if Podman is installed or will be installed
	if [[ "${SKIP_INSTALL_PODMAN}" = "1" ]] || check_podman_installed; then
		# Interactive mode with no TT_SKIP_INSTALL_METALIUM_CONTAINER set
		log "Would you like to install the TT-Metalium library using Podman?"
		if confirm "Make a selection"; then
			SKIP_INSTALL_METALIUM_CONTAINER=1
		else
			SKIP_INSTALL_METALIUM_CONTAINER=0
			SKIP_INSTALL_PODMAN=0 # If we don't want Metalium, we can skip Podman
		fi
	else
		# Podman won't be installed, so don't install Metalium
		SKIP_INSTALL_METALIUM_CONTAINER=0
		warn "Podman is not and will not be installed, skipping Podman Metalium installation"
	fi
}

# Main installation script
main() {
	echo -e "${LOGO}"
	echo # newline
	INSTALLER_VERSION="__INSTALLER_DEVELOPMENT_BUILD__" # Set to semver at release time by GitHub Actions
	log "Welcome to tenstorrent!"
	log "This is tt-installer version ${INSTALLER_VERSION}"
	log "Log is at ${LOG_FILE}"

	fetch_tt_sw_versions

	log "This script will install drivers and tooling and properly configure your tenstorrent hardware."

	if ! confirm "OK to continue?"; then
		error "Exiting."
		exit 1
	fi
	log "Starting installation"

	# Log special mode settings
	if [[ "${NON_INTERACTIVE_MODE}" = "0" ]]; then
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
	if [[ "${SKIP_INSTALL_PODMAN}" = "0" ]]; then
		warn "Podman installation will be skipped"
	fi
	if [[ "${SKIP_INSTALL_METALIUM_CONTAINER}" = "0" ]]; then
		warn "Metalium installation will be skipped"
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
		"ubuntu")
			sudo apt update
			if [[ "${IS_UBUNTU_20}" = "0" ]]; then
				# On Ubuntu 20, install python3-venv and don't install pipx
				sudo apt install -y wget git python3-pip python3-venv dkms cargo rustc jq
			else
				sudo DEBIAN_FRONTEND=noninteractive apt install -y wget git python3-pip dkms cargo rustc pipx jq
			fi
			;;
		"debian")
			# On Debian, packaged cargo and rustc are very old. Users must install them another way.
			sudo apt update
			sudo apt install -y wget git python3-pip dkms pipx jq
			;;
		"fedora")
			sudo dnf install -y wget git python3-pip python3-devel dkms cargo rust pipx jq
			;;
		"rhel"|"centos")
			sudo dnf install -y epel-release
			sudo dnf install -y wget git python3-pip python3-devel dkms cargo rust pipx jq
			;;
		*)
			error "Unsupported distribution: ${DISTRO_ID}"
			exit 1
			;;
	esac

	if [[ "${IS_UBUNTU_20}" = "0" ]]; then
		warn "Ubuntu 20 is deprecated and support will be removed in a future release!"
		warn "Metalium installation will be unavailable. To install Metalium, upgrade to Ubuntu 22+"
	fi

	if [[ "${DISTRO_ID}" = "debian" ]]; then
		warn "rustc and cargo cannot be automatically installed on Debian. Ensure the latest versions are installed before continuing."
		warn "If you are unsure how to do this, use rustup: https://rustup.rs/"
	fi

	# If jq wasn't installed before, we need to fetch these now that we have it installed
	if [[ "${HAVE_SET_TT_SW_VERSIONS}" = "1" ]]; then
		fetch_tt_sw_versions
	fi
	# If we still haven't successfully retrieved the versions, there is an error, so exit
	if [[ "${HAVE_SET_TT_SW_VERSIONS}" = "1" ]]; then
		error_exit "Cannot fetch versions of TT software. Is jq installed?"
	fi

	# Get Podman Metalium installation choice
	get_podman_metalium_choice

	# Python package installation preference
	get_new_venv_location
	get_python_choice

	# Enforce restrictions on Ubuntu 20
	if [[ "${IS_UBUNTU_20}" = "0" && "${PYTHON_CHOICE}" = "4" ]]; then
		warn "pipx installation not supported on Ubuntu 20, defaulting to virtual environment"
		PYTHON_CHOICE=2
	fi

	# Set up Python environment based on choice
	# shellcheck disable=SC2221,SC2222  # Using the "2" after a "*" for documentation and clarity,
	# but we need to tell shellcheck to ignore it
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
			INSTALLED_IN_VENV=1
			# Check Python version to determine if --break-system-packages is needed (Python 3.11+)
			PYTHON_VERSION_MINOR=$(python3 -c "import sys; print(f'{sys.version_info.minor}')")
			if [[ ${PYTHON_VERSION_MINOR} -gt 10 ]]; then # Is version greater than 3.10?
				PYTHON_INSTALL_CMD="pip install --break-system-packages"
			else
				PYTHON_INSTALL_CMD="pip install"
			fi
			;;
		4)
			log "Using pipx for isolated package installation"
			pipx ensurepath
			# Enable the pipx path in this shell session
			export PATH="${PATH}:${HOME}/.local/bin/"
			INSTALLED_IN_VENV=1
			PYTHON_INSTALL_CMD="pipx install"
			;;
		*|"2")
			log "Setting up new Python virtual environment"
			python3 -m venv "${NEW_VENV_LOCATION}"
			# shellcheck disable=SC1091 # Must exist after previous command
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
				sudo dkms remove "tenstorrent/${KMD_INSTALLED_VERSION}" --all
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
		${PYTHON_INSTALL_CMD} git+https://github.com/tenstorrent/tt-flash.git@"${FLASH_VERSION}"

		# Create FW_FILE based on FW_VERSION
		FW_FILE="fw_pack-${FW_VERSION}.fwbundle"
		FW_RELEASE_URL="https://github.com/tenstorrent/tt-firmware/releases/download"

		# Download from GitHub releases
		wget "${FW_RELEASE_URL}/v${FW_VERSION}/${FW_FILE}"

		verify_download "${FW_FILE}"

		if ! tt-flash --fw-tar "${FW_FILE}"; then
			warn "Initial firmware update failed, attempting force update"
			tt-flash --fw-tar "${FW_FILE}" --force
		fi
	fi

	# Setup HugePages
	BASE_TOOLS_URL="https://github.com/tenstorrent/tt-system-tools/releases/download"
	# Skip HugePages installation if flag is set
	if [[ "${SKIP_INSTALL_HUGEPAGES}" = "0" ]]; then
		warn "Skipping HugePages setup"
	else
		log "Setting up HugePages"
		case "${DISTRO_ID}" in
			"ubuntu"|"debian")
				TOOLS_FILENAME="tenstorrent-tools_${SYSTOOLS_VERSION}_all.deb"
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
	${PYTHON_INSTALL_CMD} git+https://github.com/tenstorrent/tt-smi@"${SMI_VERSION}"

	# Install Podman if requested
	if [[ "${SKIP_INSTALL_PODMAN}" = "0" ]]; then
		warn "Skipping Podman installation"
	else
		if ! check_podman_installed; then
			install_podman
		fi
	fi

	# Install Podman Metalium if requested
	if [[ "${SKIP_INSTALL_METALIUM_CONTAINER}" = "0" ]]; then
		warn "Skipping Podman Metalium installation"
	else
		if ! check_podman_installed; then
			warn "Podman is not installed. Cannot install Podman Metalium."
		else
			install_podman_metalium
		fi
	fi

	log "Installation completed successfully!"
	log "Installation log saved to: ${LOG_FILE}"
	if [[ "${INSTALLED_IN_VENV}" = "0" ]]; then
		warn "You'll need to run \"source ${VIRTUAL_ENV}/bin/activate\" to use tenstorrent's Python tools."
	fi

	log "Please reboot your system to complete the setup."
	log "After rebooting, try running 'tt-smi' to see the status of your hardware."
	if [[ "${SKIP_INSTALL_METALIUM_CONTAINER}" = "1" ]]; then
		log "Use 'tt-metalium' to access the Metalium programming environment"
		log "Usage examples:"
		log "  tt-metalium                   # Start an interactive shell"
		log "  tt-metalium [command]         # Run a specific command"
		log "  tt-metalium python script.py  # Run a Python script"
	fi

	# Auto-reboot if specified
	if [[ "${REBOOT_OPTION}" = "3" ]]; then
		log "Auto-reboot enabled. Rebooting now..."
		sudo reboot
	# Otherwise, ask if specified
	elif [[ "${REBOOT_OPTION}" = "1" ]]; then
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
