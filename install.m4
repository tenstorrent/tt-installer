#!/bin/bash

set -euo pipefail

# m4_ignore(
echo "This is just a script template, not the script (yet) - pass it to 'argbash' to fix this." >&2
exit 11 #)
# ARG_HELP([A one-stop-shop for installing the Tenstorrent stack])
# ARG_VERSION([echo "__INSTALLER_DEVELOPMENT_BUILD__"])
# ========================= Boolean Arguments =========================
# ARG_OPTIONAL_BOOLEAN([install-kmd],,[Kernel-Mode-Driver installation],[on])
# ARG_OPTIONAL_BOOLEAN([install-hugepages],,[Configure HugePages],[on])
# ARG_OPTIONAL_BOOLEAN([install-podman],,[Install Podman],[on])
# ARG_OPTIONAL_BOOLEAN([install-metalium-container],,[Download and install Metalium container],[on])
# ARG_OPTIONAL_BOOLEAN([update-firmware],,[Update TT device firmware],[on])

# =========================  Podman Metalium Arguments =========================
# ARG_OPTIONAL_SINGLE([metalium-image-url],,[Container image URL to pull/run],[ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-release-amd64])
# ARG_OPTIONAL_SINGLE([metalium-image-tag],,[Tag (version) of the Metalium image],[latest-rc])
# ARG_OPTIONAL_SINGLE([podman-metalium-script-dir],,[Directory where the helper wrapper will be written],["$HOME/.local/bin"])
# ARG_OPTIONAL_SINGLE([podman-metalium-script-name],,[Name of the helper wrapper script],["tt-metalium"])

# ========================= String Parameters =========================
# ARG_OPTIONAL_SINGLE([python-choice],,[Python setup strategy: active-venv, new-venv, system-python, pipx],[new-venv])
# ARG_OPTIONAL_SINGLE([reboot-option],,[Reboot policy after install: ask, never, always],[ask])

# ========================= Version Arguments =========================
# ARG_OPTIONAL_SINGLE([kmd-version],,[Specific version of TT-KMD to install],[])
# ARG_OPTIONAL_SINGLE([fw-version],,[Specific version of firmware to install],[])
# ARG_OPTIONAL_SINGLE([systools-version],,[Specific version of system tools to install],[])
# ARG_OPTIONAL_SINGLE([smi-version],,[Specific version of tt-smi to install],[])
# ARG_OPTIONAL_SINGLE([flash-version],,[Specific version of tt-flash to install],[])

# ========================= Path Arguments =========================
# ARG_OPTIONAL_SINGLE([new-venv-location],,[Path for new Python virtual environment],[$HOME/.tenstorrent-venv])

# ========================= Mode Arguments =========================
# ARG_OPTIONAL_BOOLEAN([mode-container],,[Enable container mode (skips KMD and HugePages, never reboots)],[off])
# ARG_OPTIONAL_BOOLEAN([mode-non-interactive],,[Enable non-interactive mode (no user prompts)],[off])

# ARGBASH_GO

# [ <-- needed because of Argbash

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

# ========================= Backward Compatibility Environment Variables =========================

# Support environment variables as fallbacks for backward compatibility
# If env var is set, use it; otherwise use argbash value with default

# Podman Metalium URLs and Settings
METALIUM_IMAGE_URL="${TT_METALIUM_IMAGE_URL:-${_arg_metalium_image_url}}"
METALIUM_IMAGE_TAG="${TT_METALIUM_IMAGE_TAG:-${_arg_metalium_image_tag}}"
PODMAN_METALIUM_SCRIPT_DIR="${TT_PODMAN_METALIUM_SCRIPT_DIR:-${_arg_podman_metalium_script_dir}}"
PODMAN_METALIUM_SCRIPT_NAME="${TT_PODMAN_METALIUM_SCRIPT_NAME:-${_arg_podman_metalium_script_name}}"

# String Parameters - use env var if set, otherwise argbash value
PYTHON_CHOICE="${TT_PYTHON_CHOICE:-${_arg_python_choice}}"
REBOOT_OPTION="${TT_REBOOT_OPTION:-${_arg_reboot_option}}"

# Path Parameters - use env var if set, otherwise argbash value
NEW_VENV_LOCATION="${TT_NEW_VENV_LOCATION:-${_arg_new_venv_location}}"

# Boolean Parameters - support legacy env vars for backward compatibility
# Convert env vars to argbash format if they exist
if [[ -n "${TT_INSTALL_KMD:-}" ]]; then
	if [[ "${TT_INSTALL_KMD}" == "true" || "${TT_INSTALL_KMD}" == "0" || "${TT_INSTALL_KMD}" == "on" ]]; then
		_arg_install_kmd="on"
	else
		_arg_install_kmd="off"
	fi
fi

if [[ -n "${TT_INSTALL_HUGEPAGES:-}" ]]; then
	if [[ "${TT_INSTALL_HUGEPAGES}" == "true" || "${TT_INSTALL_HUGEPAGES}" == "0" || "${TT_INSTALL_HUGEPAGES}" == "on" ]]; then
		_arg_install_hugepages="on"
	else
		_arg_install_hugepages="off"
	fi
fi

if [[ -n "${TT_INSTALL_PODMAN:-}" ]]; then
	if [[ "${TT_INSTALL_PODMAN}" == "true" || "${TT_INSTALL_PODMAN}" == "0" || "${TT_INSTALL_PODMAN}" == "on" ]]; then
		_arg_install_podman="on"
	else
		_arg_install_podman="off"
	fi
fi

if [[ -n "${TT_INSTALL_METALIUM_CONTAINER:-}" ]]; then
	if [[ "${TT_INSTALL_METALIUM_CONTAINER}" == "true" || "${TT_INSTALL_METALIUM_CONTAINER}" == "0" || "${TT_INSTALL_METALIUM_CONTAINER}" == "on" ]]; then
		_arg_install_metalium_container="on"
	else
		_arg_install_metalium_container="off"
	fi
fi

if [[ -n "${TT_UPDATE_FIRMWARE:-}" ]]; then
	if [[ "${TT_UPDATE_FIRMWARE}" == "true" || "${TT_UPDATE_FIRMWARE}" == "0" || "${TT_UPDATE_FIRMWARE}" == "on" ]]; then
		_arg_update_firmware="on"
	else
		_arg_update_firmware="off"
	fi
fi

if [[ -n "${TT_MODE_NON_INTERACTIVE:-}" ]]; then
	if [[ "${TT_MODE_NON_INTERACTIVE}" == "true" || "${TT_MODE_NON_INTERACTIVE}" == "0" || "${TT_MODE_NON_INTERACTIVE}" == "on" ]]; then
		_arg_mode_non_interactive="on"
	else
		_arg_mode_non_interactive="off"
	fi
fi

# If container mode is enabled, disable KMD and HugePages
if [[ "${_arg_mode_container}" = "on" ]]; then
	_arg_install_kmd="off"
	_arg_install_hugepages="off" # Both KMD and HugePages must live on the host kernel
	_arg_install_podman="off" # No podman in podman
	REBOOT_OPTION="never" # Do not reboot
fi

# In non-interactive mode, set reboot default if not specified
if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
	# In non-interactive mode, we can't ask the user for anything
	# So if they don't provide a reboot choice we will pick a default
	if [[ "${REBOOT_OPTION}" = "ask" ]]; then
		REBOOT_OPTION="never" # Do not reboot
	fi
fi

SYSTEMD_NOW="${TT_SYSTEMD_NOW:---now}"
SYSTEMD_NO="${TT_SYSTEMD_NO:-0}"
TT_PIPX_ENSUREPATH_EXTRAS="${PIPX_ENSUREPATH_EXTRAS:- }"
TT_PIPX_INSTALL_EXTRAS="${PIPX_INSTALL_EXTRAS:- }"

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

# argbash workaround: close square brackets ]]]]]

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
	if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
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
	# In non-interactive mode, use the provided argument
	if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
		log "Non-interactive mode, using Python installation method: ${_arg_python_choice}"
		return
	fi

	log "How would you like to install Python packages?"
	# Interactive mode - show current choice and allow override
	while true; do
		echo "1) active-venv: Use the active virtual environment"
		echo "2) new-venv: [DEFAULT] Create a new Python virtual environment (venv) at ${NEW_VENV_LOCATION}"
		echo "3) system-python: Use the system pathing, available for multiple users. *** NOT RECOMMENDED UNLESS YOU ARE SURE ***"
		if [[ "${IS_UBUNTU_20}" != "0" ]]; then
			echo "4) pipx: Use pipx for isolated package installation"
		fi
		read -rp "Enter your choice (1-4) or press enter for default (${_arg_python_choice}): " user_choice
		echo # newline

		# If user provided no value, use default and exit
		if [[ -z "${user_choice}" ]]; then
			break
		fi

		# Process user choice
		case "${user_choice}" in
			1|active-venv)
				PYTHON_CHOICE="active-venv"
				break
				;;
			2|new-venv)
				PYTHON_CHOICE="new-venv"
				break
				;;
			3|system-python)
				PYTHON_CHOICE="system-python"
				break
				;;
			4|pipx)
				PYTHON_CHOICE="pipx"
				break
				;;
			*)
				warn "Invalid choice '${user_choice}'. Please try again."
				;;
		esac
	done
}

fetch_tt_sw_versions() {
	# Use environment variable if set, then argbash version if present, otherwise latest
	if [[ -n "${TT_KMD_VERSION:-}" ]]; then
		KMD_VERSION="${TT_KMD_VERSION}"
	elif [[ -n "${_arg_kmd_version}" ]]; then
		KMD_VERSION="${_arg_kmd_version}"
	else
		KMD_VERSION="$(fetch_latest_kmd_version)"
	fi
	if [[ -n "${TT_FW_VERSION:-}" ]]; then
		FW_VERSION="${TT_FW_VERSION}"
	elif [[ -n "${_arg_fw_version}" ]]; then
		FW_VERSION="${_arg_fw_version}"
	else
		FW_VERSION="$(fetch_latest_fw_version)"
	fi
	if [[ -n "${TT_SYSTOOLS_VERSION:-}" ]]; then
		SYSTOOLS_VERSION="${TT_SYSTOOLS_VERSION}"
	elif [[ -n "${_arg_systools_version}" ]]; then
		SYSTOOLS_VERSION="${_arg_systools_version}"
	else
		SYSTOOLS_VERSION="$(fetch_latest_systools_version)"
	fi
	if [[ -n "${TT_SMI_VERSION:-}" ]]; then
		SMI_VERSION="${TT_SMI_VERSION}"
	elif [[ -n "${_arg_smi_version}" ]]; then
		SMI_VERSION="${_arg_smi_version}"
	else
		SMI_VERSION="$(fetch_latest_smi_version)"
	fi
	if [[ -n "${TT_FLASH_VERSION:-}" ]]; then
		FLASH_VERSION="${TT_FLASH_VERSION}"
	elif [[ -n "${_arg_flash_version}" ]]; then
		FLASH_VERSION="${_arg_flash_version}"
	else
		FLASH_VERSION="$(fetch_latest_flash_version)"
	fi

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
	# If we're on Ubuntu 20, Podman is not available - force disable
	if [[ "${IS_UBUNTU_20}" = "0" ]]; then
		_arg_install_metalium_container="off"
		_arg_install_podman="off"
		return
	fi

	# In non-interactive mode, use the provided arguments
	if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
		log "Non-interactive mode, using Podman Metalium installation preference: ${_arg_install_metalium_container}"
		return
	fi

	# Only ask if Podman is installed or will be installed
	if [[ "${_arg_install_podman}" = "on" ]] || check_podman_installed; then
		# Interactive mode - allow override
		log "Current Metalium installation setting: ${_arg_install_metalium_container}"
		log "Would you like to install the TT-Metalium library using Podman?"
		if confirm "Install Metalium"; then
			_arg_install_metalium_container="on"
		else
			_arg_install_metalium_container="off"
			_arg_install_podman="off" # If we don't want Metalium, we can skip Podman
		fi
	else
		# Podman won't be installed, so don't install Metalium
		_arg_install_metalium_container="off"
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
	if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
		warn "Running in non-interactive mode"
	fi
	if [[ "${_arg_mode_container}" = "on" ]]; then
		warn "Running in container mode"
	fi
	if [[ "${_arg_install_kmd}" = "off" ]]; then
		warn "KMD installation will be skipped"
	fi
	if [[ "${_arg_install_hugepages}" = "off" ]]; then
		warn "HugePages setup will be skipped"
	fi
	if [[ "${_arg_install_podman}" = "off" ]]; then
		warn "Podman installation will be skipped"
	fi
	if [[ "${_arg_install_metalium_container}" = "off" ]]; then
		warn "Metalium installation will be skipped"
	fi
	if [[ "${_arg_update_firmware}" = "off" ]]; then
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
	get_python_choice

	# Enforce restrictions on Ubuntu 20
	if [[ "${IS_UBUNTU_20}" = "0" && "${PYTHON_CHOICE}" = "pipx" ]]; then
		warn "pipx installation not supported on Ubuntu 20, defaulting to virtual environment"
		PYTHON_CHOICE="new-venv"
	fi

	# Set up Python environment based on choice
	case ${PYTHON_CHOICE} in
		"active-venv")
			if [[ ! -n "${VIRTUAL_ENV:-}" ]]; then
				error "No active virtual environment detected!"
				error "Please activate your virtual environment first and try again"
				exit 1
			fi
			log "Using active virtual environment: ${VIRTUAL_ENV}"
			INSTALLED_IN_VENV=0
			PYTHON_INSTALL_CMD="pip install"
			;;
		"system-python")
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
		"pipx")
			log "Using pipx for isolated package installation"
			pipx ensurepath
			# Enable the pipx path in this shell session
			export PATH="${PATH}:${HOME}/.local/bin/"
			INSTALLED_IN_VENV=1
			PYTHON_INSTALL_CMD="pipx install"
			;;
		*|"new-venv")
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
	if [[ "${_arg_install_kmd}" = "off" ]]; then
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
	if [[ "${_arg_update_firmware}" = "off" ]]; then
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
	if [[ "${_arg_install_hugepages}" = "off" ]]; then
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
				if [[ "${SYSTEMD_NO}" != 0 ]]
				then
					sudo systemctl enable ${SYSTEMD_NOW} tenstorrent-hugepages.service
					sudo systemctl enable ${SYSTEMD_NOW} 'dev-hugepages\x2d1G.mount'
				fi
				;;
			"fedora"|"rhel"|"centos")
				TOOLS_FILENAME="tenstorrent-tools-${SYSTOOLS_VERSION}-1.noarch.rpm"
				TOOLS_URL="${BASE_TOOLS_URL}/v${SYSTOOLS_VERSION}/${TOOLS_FILENAME}"
				wget "${TOOLS_URL}"
				verify_download "${TOOLS_FILENAME}"
				sudo dnf install -y "${TOOLS_FILENAME}"
				if [[ "${SYSTEMD_NO}" != 0 ]]
				then
					sudo systemctl enable ${SYSTEMD_NOW} tenstorrent-hugepages.service
					sudo systemctl enable ${SYSTEMD_NOW} 'dev-hugepages\x2d1G.mount'
				fi
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
	if [[ "${_arg_install_podman}" = "off" ]]; then
		warn "Skipping Podman installation"
	else
		if ! check_podman_installed; then
			install_podman
		fi
	fi

	# Install Podman Metalium if requested
	if [[ "${_arg_install_metalium_container}" = "off" ]]; then
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
	if [[ "${_arg_install_metalium_container}" = "on" ]]; then
		log "Use 'tt-metalium' to access the Metalium programming environment"
		log "Usage examples:"
		log "  tt-metalium                   # Start an interactive shell"
		log "  tt-metalium [command]         # Run a specific command"
		log "  tt-metalium python script.py  # Run a Python script"
	fi

	# Auto-reboot if specified
	if [[ "${REBOOT_OPTION}" = "always" ]]; then
		log "Auto-reboot enabled. Rebooting now..."
		sudo reboot
	# Otherwise, ask if specified
	elif [[ "${REBOOT_OPTION}" = "ask" ]]; then
		if confirm "Would you like to reboot now?"; then
			log "Rebooting..."
			sudo reboot
		fi
	fi
}

# Start installation
main

# ] <-- needed because of Argbash

# vim: noai:ts=4:sw=4:ft=bash
