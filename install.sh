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
	local latest_kmd
	latest_kmd=$(git ls-remote --tags --refs "${TT_KMD_GIT_URL}" | awk -F/ '{print $NF}' | sort -V | tail -n1)
	echo "${latest_kmd#ttkmd-}"
}

# Fetch lastest FW version
TT_FW_GIT_URL="https://github.com/tenstorrent/tt-firmware.git"
fetch_latest_fw_version() {
	local latest_fw
	latest_fw=$(git ls-remote --tags --refs "${TT_FW_GIT_URL}" | awk -F/ '{print $NF}' | sort -V | tail -n1)
	echo "${latest_fw#v}" # Remove 'v' prefix if present
}

# Fetch latest systools version
# Currently unused due to systools tags being broken
TT_SYSTOOLS_GIT_URL="https://github.com/tenstorrent/tt-system-tools.git"
fetch_latest_systools_version() {
	local latest_systools
	latest_systools=$(git ls-remote --tags --refs "${TT_SYSTOOLS_GIT_URL}" | awk -F/ '{print $NF}' | sort -V | tail -n1)
	echo "${latest_systools#v}" # Remove 'upstream/' prefix
}

# Fetch latest Metalium version
TT_METALIUM_REGISTRY_URL="ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-amd64-release"
fetch_latest_metalium_version() {
	# Default to "latest" tag since we're using GitHub Container Registry
	echo "latest"
}

# Skip KMD installation flag (set to 0 to skip)
SKIP_INSTALL_KMD=${TT_SKIP_INSTALL_KMD:-1}

# Skip HugePages installation flag (set to 0 to skip)
SKIP_INSTALL_HUGEPAGES=${TT_SKIP_INSTALL_HUGEPAGES:-1}

# Skip tt-flash and firmware update flag (set to 0 to skip)
SKIP_UPDATE_FIRMWARE=${TT_SKIP_UPDATE_FIRMWARE:-1}

# Skip Metalium Docker installation flag (set to 0 to skip)
SKIP_INSTALL_METALIUM=${TT_SKIP_INSTALL_METALIUM:-1}

# Developer mode for Metalium containers (set to 1 to enable extra permissions)
METALIUM_DEV_MODE=${TT_METALIUM_DEV_MODE:-0}

# Optional assignment- uses TT_ envvar version if present, otherwise latest
KMD_VERSION="${TT_KMD_VERSION:-$(fetch_latest_kmd_version)}"
FW_VERSION="${TT_FW_VERSION:-$(fetch_latest_fw_version)}"
SYSTOOLS_VERSION="${TT_SYSTOOLS_VERSION:-$(fetch_latest_systools_version)}"
METALIUM_VERSION="${TT_METALIUM_VERSION:-$(fetch_latest_metalium_version)}"

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
REBOOT_OPTION_TXT[3]="Always reboot"

# Container mode flag (set to 0 to enable, which skips KMD and HugePages and never reboots)
CONTAINER_MODE=${TT_MODE_CONTAINER:-1}
# If container mode is enabled, skip KMD, HugePages, and Metalium (to avoid Docker-in-Docker)
if [[ "${CONTAINER_MODE}" = "0" ]]; then
	SKIP_INSTALL_KMD=0
	SKIP_INSTALL_HUGEPAGES=0
	SKIP_INSTALL_METALIUM=0
	REBOOT_OPTION=2 # Do not reboot
fi

# Non-interactive mode flag (set to 0 to enable)
NON_INTERATIVE_MODE=${TT_MODE_NON_INTERATIVE:-1}
if [[ "${NON_INTERATIVE_MODE}" = "0" ]]; then
	# In non-interactive mode, we can't ask the user for anything
	# So if they don't provide a reboot choice we will pick a default
	if [[ "${REBOOT_OPTION}" = "1" ]]; then
		REBOOT_OPTION=2 # Do not reboot
	fi
fi

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
		# shellcheck source=/dev/null
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
	if [[ "${NON_INTERATIVE_MODE}" = "0" ]]; then
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
	elif [[ "${NON_INTERATIVE_MODE}" = "0" ]]; then
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

# Check if Docker is installed and install if needed
install_docker_if_needed() {
	if command -v docker &> /dev/null; then
		log "Docker is already installed"
		
		# Check if user is in docker group, if not add them
		if ! groups "${USER}" | grep -q '\bdocker\b'; then
			log "Adding user to docker group"
			sudo usermod -aG docker "${USER}"
			warn "You may need to log out and back in for docker group membership to take effect"
		fi
		
		# Ensure docker service is running
		if ! sudo systemctl is-active --quiet docker; then
			log "Starting docker service"
			sudo systemctl start docker
			sudo systemctl enable docker
		fi
		
		return 0
	fi
	
	log "Installing Docker"
	
	case "${DISTRO_ID}" in
		"ubuntu"|"debian")
			# Install Docker dependencies (if not already part of base packages)
			sudo apt update
			sudo apt install -y ca-certificates curl gnupg
			
			# Add Docker's official GPG key
			sudo install -m 0755 -d /etc/apt/keyrings
			curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
			sudo chmod a+r /etc/apt/keyrings/docker.gpg
			
			# Add the repository to sources list
			echo \
			"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO_ID} \
			$(. /etc/os-release && echo "${VERSION_CODENAME}") stable" | \
			sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
			
			# Update and install Docker
			sudo apt update
			sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
			;;
		"fedora"|"rhel"|"centos")
			# Install Docker via DNF on Fedora/RHEL/CentOS
			sudo dnf -y install dnf-plugins-core
			sudo dnf config-manager --add-repo "https://download.docker.com/linux/${DISTRO_ID}/docker-ce.repo"
			sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
			;;
		*)
			error "Unsupported distribution for Docker installation: ${DISTRO_ID}"
			return 1
			;;
	esac
	
	# Enable and start Docker service
	sudo systemctl enable docker
	sudo systemctl start docker
	
	# Add user to docker group to run Docker without sudo
	sudo usermod -aG docker "${USER}"
	
	warn "You may need to log out and back in for docker group membership to take effect"
	
	return 0
}

# Create a wrapper script for tt-metalium
create_metalium_wrapper_script() {
	local bin_dir="${HOME}/.local/bin"
	mkdir -p "${bin_dir}"
	
	local script_path="${bin_dir}/tt-metalium"
	local metalium_image="${TT_METALIUM_REGISTRY_URL}:${METALIUM_VERSION}"
	
	# Create the wrapper script with appropriate options based on dev mode
	if [[ "${METALIUM_DEV_MODE}" = "1" ]]; then
		log "Creating tt-metalium wrapper script with developer mode enabled"
		cat > "${script_path}" << EOF
#!/bin/bash
# Wrapper script for TT-Metalium Docker container with developer mode enabled

# Default image version
METALIUM_VERSION="${METALIUM_VERSION}"

# Use custom version if specified
if [[ -n "\${TT_METALIUM_VERSION}" ]]; then
    METALIUM_VERSION="\${TT_METALIUM_VERSION}"
fi

# Run TT-Metalium Docker container with additional developer permissions
docker run --rm -it \\
    --device=/dev/tenstorrent\\* \\
    --cap-add=SYS_PTRACE \\
    --security-opt seccomp=unconfined \\
    --user="\$(id -u):\$(id -g)" \\
    -v "\${HOME}:/home/\${USER}" \\
    -v /tmp:/tmp \\
    -v /dev/hugepages-1G:/dev/hugepages-1G \\
    -w "/home/\${USER}" \\
    -e HOME="/home/\${USER}" \\
    -e USER="\${USER}" \\
    ${TT_METALIUM_REGISTRY_URL}:\${METALIUM_VERSION} "\$@"
EOF
	else
		log "Creating standard tt-metalium wrapper script"
		cat > "${script_path}" << EOF
#!/bin/bash
# Wrapper script for TT-Metalium Docker container

# Default image version
METALIUM_VERSION="${METALIUM_VERSION}"

# Use custom version if specified
if [[ -n "\${TT_METALIUM_VERSION}" ]]; then
    METALIUM_VERSION="\${TT_METALIUM_VERSION}"
fi

# Run TT-Metalium Docker container with standard options
docker run --rm -it \\
    --device=/dev/tenstorrent\\* \\
    -v "\${HOME}:/home/\${USER}" \\
    -v /dev/hugepages-1G:/dev/hugepages-1G \\
    -w "/home/\${USER}" \\
    -e HOME="/home/\${USER}" \\
    -e USER="\${USER}" \\
    ${TT_METALIUM_REGISTRY_URL}:\${METALIUM_VERSION} "\$@"
EOF
	fi
	
	chmod +x "${script_path}"
	
	# Add script directory to PATH if not already there
	if ! echo "${PATH}" | grep -q "${bin_dir}"; then
		log "Adding ${bin_dir} to PATH in .bashrc"
		echo "export PATH=\"\${PATH}:${bin_dir}\"" >> "${HOME}/.bashrc"
		warn "You'll need to source your .bashrc or restart your shell to use tt-metalium command"
	fi
}

# Install TT-Metalium Docker image
install_metalium_docker() {
	log "Installing TT-Metalium Docker image (version ${METALIUM_VERSION})"
	
	# Pull the Metalium Docker image from the correct registry
	docker pull "${TT_METALIUM_REGISTRY_URL}:${METALIUM_VERSION}"
	
	# Create the tt-metalium wrapper script
	create_metalium_wrapper_script
	
	log "TT-Metalium Docker image installed successfully"
	log "You can now use 'tt-metalium' command to start a Metalium container"
}

# Function to install base packages based on distro
install_base_packages() {
	log "Installing base packages"
	case "${DISTRO_ID}" in
		"ubuntu"|"debian")
			sudo apt update
			if [[ "${IS_UBUNTU_20}" != "0" ]]; then
				sudo apt install -y wget git python3-pip dkms cargo rustc pipx
				# Install Docker dependencies if we're going to install Docker
				if [[ "${SKIP_INSTALL_METALIUM}" != "0" ]]; then
					sudo apt install -y ca-certificates curl gnupg
				fi
			# On Ubuntu 20, install python3-venv and don't install pipx
			else
				sudo apt install -y wget git python3-pip python3-venv dkms cargo rustc
				# Install Docker dependencies if needed
				if [[ "${SKIP_INSTALL_METALIUM}" != "0" ]]; then
					sudo apt install -y ca-certificates curl gnupg
				fi
			fi
			;;
		"fedora")
			sudo dnf install -y wget git python3-pip python3-devel dkms cargo rust pipx
			# Install Docker dependencies if needed
			if [[ "${SKIP_INSTALL_METALIUM}" != "0" ]]; then
				sudo dnf install -y dnf-plugins-core
			fi
			;;
		"rhel"|"centos")
			sudo dnf install -y epel-release
			sudo dnf install -y wget git python3-pip python3-devel dkms cargo rust pipx
			# Install Docker dependencies if needed
			if [[ "${SKIP_INSTALL_METALIUM}" != "0" ]]; then
				sudo dnf install -y dnf-plugins-core
			fi
			;;
		*)
			error "Unsupported distribution: ${DISTRO_ID}"
			exit 1
			;;
	esac

	if [[ "${IS_UBUNTU_20}" = "0" ]]; then
		warn "Ubuntu 20 is deprecated and support will be removed in a future release!"
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
	log "  Metalium: ${METALIUM_VERSION}"

	# Log special mode settings
	if [[ "${NON_INTERATIVE_MODE}" = "0" ]]; then
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
	if [[ "${SKIP_INSTALL_METALIUM}" = "0" ]]; then
		warn "TT-Metalium installation will be skipped"
	fi
	if [[ "${METALIUM_DEV_MODE}" = "1" && "${SKIP_INSTALL_METALIUM}" != "0" ]]; then
		warn "TT-Metalium will be installed with developer mode enabled"
	fi

	log "Checking for sudo permissions... (may request password)"
	check_has_sudo_perms

	# Check distribution and install base packages
	detect_distro
	install_base_packages

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
			INSTALLED_IN_VENV=1
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
			# Enable the pipx path in this shell session
			export PATH="${PATH}:${HOME}/.local/bin/"
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
		warn "Skipping KMD installation"
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
		warn "Skipping TT-Flash and firmware update installation"
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

	# Install TT-Metalium Docker image
	# Skip Metalium installation if flag is set or if in container mode
	if [[ "${SKIP_INSTALL_METALIUM}" = "0" ]]; then
		warn "Skipping TT-Metalium installation"
	else
		log "Setting up Docker for TT-Metalium"
		if install_docker_if_needed; then
			install_metalium_docker
		else
			error "Failed to install Docker. Skipping TT-Metalium installation."
		fi
	fi

	log "Installation completed successfully!"
	log "Installation log saved to: ${LOG_FILE}"
	if [[ "${INSTALLED_IN_VENV}" = "0" ]]; then
		warn "You'll need to run \"source ${VIRTUAL_ENV}/bin/activate\" to use tenstorrent tools."
	fi
	log "Please reboot your system to complete the setup."
	log "After rebooting, try running 'tt-smi' to see the status of your hardware."
	
	if [[ "${SKIP_INSTALL_METALIUM}" != "0" ]]; then
		log "To use TT-Metalium, run the 'tt-metalium' command after rebooting."
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