#!/bin/bash
# shellcheck disable=SC2317

# SPDX-FileCopyrightText: © 2025 Tenstorrent AI ULC
# SPDX-License-Identifier: Apache-2.0

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
# ARG_OPTIONAL_BOOLEAN([install-tt-flash],,[Install tt-flash for updating device firmware],[on])
# ARG_OPTIONAL_BOOLEAN([install-tt-topology],,[Install tt-topology (Wormhole only)],[off])
# ARG_OPTIONAL_BOOLEAN([install-sfpi],,[Install SFPI],[on])

# =========================  Podman Metalium Arguments =========================
# ARG_OPTIONAL_SINGLE([metalium-image-url],,[Container image URL to pull/run],[ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-release-amd64])
# ARG_OPTIONAL_SINGLE([metalium-image-tag],,[Tag (version) of the Metalium image],[latest-rc])
# ARG_OPTIONAL_SINGLE([podman-metalium-script-dir],,[Directory where the helper wrapper will be written],["$HOME/.local/bin"])
# ARG_OPTIONAL_SINGLE([podman-metalium-script-name],,[Name of the helper wrapper script],["tt-metalium"])
# ARG_OPTIONAL_BOOLEAN([install-metalium-models-container],,[Install additional TT-Metalium container for running model demos],[off])

# ========================= String Arguments =========================
# ARG_OPTIONAL_SINGLE([python-choice],,[Python setup strategy: active-venv, new-venv, system-python, pipx],[new-venv])
# ARG_OPTIONAL_SINGLE([reboot-option],,[Reboot policy after install: ask, never, always],[ask])
# ARG_OPTIONAL_SINGLE([update-firmware],,[Update TT device firmware: on, off, force],[on])
# ARG_OPTIONAL_SINGLE([github-token],,[Optional GitHub API auth token],[])

# ========================= Version Arguments =========================
# ARG_OPTIONAL_SINGLE([kmd-version],,[Specific version of TT-KMD to install],[])
# ARG_OPTIONAL_SINGLE([fw-version],,[Specific version of firmware to install],[])
# ARG_OPTIONAL_SINGLE([systools-version],,[Specific version of system tools to install],[])
# ARG_OPTIONAL_SINGLE([smi-version],,[Specific version of tt-smi to install],[])
# ARG_OPTIONAL_SINGLE([flash-version],,[Specific version of tt-flash to install],[])
# ARG_OPTIONAL_SINGLE([topology-version],,[Specific version of tt-topology to install],[])
# ARG_OPTIONAL_SINGLE([sfpi-version],,[Specific version of SFPI to install],[])

# ========================= Path Arguments =========================
# ARG_OPTIONAL_SINGLE([new-venv-location],,[Path for new Python virtual environment],[$HOME/.tenstorrent-venv])

# ========================= Mode Arguments =========================
# ARG_OPTIONAL_BOOLEAN([mode-container],,[Enable container mode (skips KMD, HugePages, and SFPI, never reboots)],[off])
# ARG_OPTIONAL_BOOLEAN([mode-non-interactive],,[Enable non-interactive mode (no user prompts)],[off])
# ARG_OPTIONAL_BOOLEAN([verbose],,[Enable verbose output for debugging])
# ARG_OPTIONAL_BOOLEAN([mode-repository-beta],,[BETA: Use external repository for package installation.],[off])

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

KERNEL_LISTING_DEBIAN=$( cat << EOF
	apt list --installed |
	grep linux-image |
	awk 'BEGIN { FS="/"; } { print \$1; }' |
	sed 's/^linux-image-//g' |
	grep -v "^generic$\|^generic-hwe-[0-9]\{2,\}\.[0-9]\{2,\}$\|virtual"
EOF
)

KERNEL_LISTING_UBUNTU=$( cat << EOF
	apt list --installed |
	grep linux-image |
	awk 'BEGIN { FS="/"; } { print \$1; }' |
	sed 's/^linux-image-//g' |
	grep -v "^generic$\|^generic-hwe-[0-9]\{2,\}\.[0-9]\{2,\}$\|virtual"
EOF
)
KERNEL_LISTING_FEDORA="rpm -qa | grep \"^kernel.*-devel\" | grep -v \"\-devel-matched\" | sed 's/^kernel-devel-//'"
KERNEL_LISTING_EL="rpm -qa | grep \"^kernel.*-devel\" | grep -v \"\-devel-matched\" | sed 's/^kernel-devel-//'"

# ========================= GIT URLs =========================

# ========================= Repository Configuration =========================

# GitHub repository URLs
TT_KMD_GH_REPO="tenstorrent/tt-kmd"
TT_FW_GH_REPO="tenstorrent/tt-firmware"
TT_SYSTOOLS_GH_REPO="tenstorrent/tt-system-tools"
TT_SMI_GH_REPO="tenstorrent/tt-smi"
TT_FLASH_GH_REPO="tenstorrent/tt-flash"
TT_TOPOLOGY_GH_REPO="tenstorrent/tt-topology"
TT_SFPI_GH_REPO="tenstorrent/sfpi"

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

# If container mode is enabled, disable KMD, HugePages, and SFPI
# shellcheck disable=SC2154
if [[ "${_arg_mode_container}" = "on" ]]; then
	_arg_install_kmd="off"
	_arg_install_hugepages="off" # Both KMD and HugePages must live on the host kernel
	_arg_install_podman="off" # No podman in podman
	_arg_install_sfpi="off"
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

# For the repository mode beta, we will disable the existing install functions
# and call a new function which installs the dependencies using the APT repo.
# shellcheck disable=SC2154
if [[ "${_arg_mode_repository_beta}" = "on" ]]; then
	_arg_install_hugepages="off"
	_arg_install_sfpi="off"
	_arg_install_kmd="off"
	export INSTALL_TT_REPOS="on"
	export INSTALL_SW_FROM_REPOS="on"
fi

SYSTEMD_NOW="${TT_SYSTEMD_NOW:---now}"
SYSTEMD_NO="${TT_SYSTEMD_NO:-1}"
PIPX_ENSUREPATH_EXTRAS="${TT_PIPX_ENSUREPATH_EXTRAS:- }"
PIPX_INSTALL_EXTRAS="${TT_PIPX_INSTALL_EXTRAS:- }"

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
    if command -v doas >/dev/null 2>&1; then
        if doas true 2>/dev/null; then
            ROOT_CMD="doas"
            return
        fi
    fi

    if command -v sudo >/dev/null 2>&1; then
        if sudo -n true 2>/dev/null; then
            ROOT_CMD="sudo"
            return
        else
            error "Cannot use sudo , exiting..."
            exit 1
        fi
    fi

    error "Neither doas nor sudo is available or permitted, exiting..."
    exit 1
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

# Generic function to fetch latest version from any GitHub repository
# Usage: fetch_latest_version <repo> <prefix_to_remove>
# Returns: version string with prefix removed, or exits with error code
fetch_latest_version() {
	local repo="$1"
	local prefix_to_remove="${2:-}"
	
	if ! command -v jq &> /dev/null; then
		return 1  # jq not installed
	fi
	
	local response
	local response_headers
	local response_body
	local latest_version
	
	# Choose curl verbosity based on verbose flag
	local curl_verbose_flag="-s"
	# shellcheck disable=SC2154
	if [[ "${_arg_verbose}" = "on" ]]; then
		curl_verbose_flag="-v"
	fi
	
	# Use -i to include headers in output for rate limit detection
	if [[ -n "${_arg_github_token}" ]]; then
		response=$(curl "${curl_verbose_flag}" -i --request GET \
		    	   -H "Authorization: token ${_arg_github_token}" \
				   https://api.github.com/repos/"${repo}"/releases/latest)
	else
		response=$(curl "${curl_verbose_flag}" -i --request GET \
				  https://api.github.com/repos/"${repo}"/releases/latest)
	fi
	
	# Split response into headers and body
	response_headers=$(echo "${response}" | sed '/^\r*$/,$d')
	response_body=$(echo "${response}" | sed '1,/^\r*$/d')
	
	# Check for GitHub API rate limit
	if echo "${response_headers}" | grep -qi "x-ratelimit-remaining: 0"; then
		return 2  # GitHub API rate limit exceeded
	fi
	
	# Check if response body is valid JSON
	if ! echo "${response_body}" | jq . >/dev/null 2>&1; then
		return 3  # Invalid JSON response
	fi
	
	latest_version=$(echo "${response_body}" | jq -r '.tag_name' 2>/dev/null)

	# Check if we got a valid tag_name
	if [[ -z "${latest_version}" || "${latest_version}" == "null" ]]; then
		return 4  # No tag_name found
	fi
	
	# Remove prefix if specified
	if [[ -n "${prefix_to_remove}" ]]; then
		echo "${latest_version#"${prefix_to_remove}"}"
	else
		echo "${latest_version}"
	fi
	
	return 0
}

# Helper function to handle version fetch errors
handle_version_fetch_error() {
	local component="$1"
	local error_code="$2"
	local repo="$3"
	
	case ${error_code} in
		1)
			error "jq command not found!"
			error "Please ensure jq is installed: sudo apt install jq (or equivalent for your distro)"
			error "Failed to fetch ${component} version."
			;;
		2)
			error "GitHub API rate limit exceeded"
			error "You have exceeded the GitHub API rate limit (60 requests per hour for unauthenticated requests)"
			error "Repository: ${repo}"
			error "Failed to fetch ${component} version."
			;;
		3)
			error "GitHub API returned invalid JSON"
			error "This may be a network issue or other API issue"
			error "Repository: ${repo}"
			error "Failed to fetch ${component} version."
			;;
		4)
			error "No valid tag_name found in API response"
			error "The repository may not have any releases or the API response is malformed"
			error "Repository: ${repo}"
			error "Failed to fetch ${component} version."
			;;
		*)
			error "Unknown error (code ${error_code})"
			error "Repository: ${repo}"
			error "Failed to fetch ${component} version."
			;;
	esac
}

fetch_tt_sw_versions() {
	local fetch_errors=0
	
	# Component configuration: env_var:arg_var:version_var:display_name:repo:prefix
	local components=(
		"TT_KMD_VERSION:_arg_kmd_version:KMD_VERSION:TT-KMD:${TT_KMD_GH_REPO}:ttkmd-"
		"TT_FW_VERSION:_arg_fw_version:FW_VERSION:Firmware:${TT_FW_GH_REPO}:v"
		"TT_SYSTOOLS_VERSION:_arg_systools_version:SYSTOOLS_VERSION:System Tools:${TT_SYSTOOLS_GH_REPO}:v"
		"TT_SMI_VERSION:_arg_smi_version:SMI_VERSION:tt-smi:${TT_SMI_GH_REPO}:"
		"TT_FLASH_VERSION:_arg_flash_version:FLASH_VERSION:tt-flash:${TT_FLASH_GH_REPO}:"
		"TT_SFPI_VERSION:_arg_sfpi_version:SFPI_VERSION:SFPI:${TT_SFPI_GH_REPO}:v"
	)
	
	# Process each component
	for component_config in "${components[@]}"; do
		IFS=':' read -r env_var arg_var version_var display_name repo prefix <<< "${component_config}"
		
		# Use environment variable if set, then argbash version if present, otherwise latest
		if [[ -n "${!env_var:-}" ]]; then
			declare -g "${version_var}=${!env_var}"
		elif [[ -n "${!arg_var}" ]]; then
			declare -g "${version_var}=${!arg_var}"
		else
			local version_result
			if version_result=$(fetch_latest_version "${repo}" "${prefix}"); then
				declare -g "${version_var}=${version_result}"
			else
				local exit_code=$?
				handle_version_fetch_error "${display_name}" "${exit_code}" "${repo}"
				fetch_errors=1
			fi
		fi
	done

	# If there were fetch errors, exit early
	if [[ ${fetch_errors} -eq 1 ]]; then
		HAVE_SET_TT_SW_VERSIONS=1
		error "*** Failed to fetch software versions due to the errors above!"
		error_exit "Visit https://github.com/tenstorrent/tt-installer/wiki/Common-Problems#software-versions-are-empty-or-null for troubleshooting help."
	fi

	# Validate all version variables are properly set (not empty or "null")
	if [[ -n "${KMD_VERSION}" && "${KMD_VERSION}" != "null" && \
	      -n "${FW_VERSION}" && "${FW_VERSION}" != "null" && \
	      -n "${SYSTOOLS_VERSION}" && "${SYSTOOLS_VERSION}" != "null" && \
	      -n "${SMI_VERSION}" && "${SMI_VERSION}" != "null" && \
	      -n "${FLASH_VERSION}" && "${FLASH_VERSION}" != "null" && \
	      -n "${SFPI_VERSION}" && "${SFPI_VERSION}" != "null" ]]; then
		HAVE_SET_TT_SW_VERSIONS=0
		log "Using software versions:"
		log "  TT-KMD: ${KMD_VERSION}"
		log "  Firmware: ${FW_VERSION}"
		log "  System Tools: ${SYSTOOLS_VERSION}"
		log "  tt-smi: ${SMI_VERSION#v}"
		log "  tt-flash: ${FLASH_VERSION#v}"
		log "  SFPI: ${SFPI_VERSION#v}"
	else
		HAVE_SET_TT_SW_VERSIONS=1
		error "*** Software versions are empty or null after successful fetch!"
		error "  TT-KMD: '${KMD_VERSION}'"
		error "  Firmware: '${FW_VERSION}'"
		error "  System Tools: '${SYSTOOLS_VERSION}'"
		error "  tt-smi: '${SMI_VERSION}'"
		error "  tt-flash: '${FLASH_VERSION}'"
		error "  SFPI: '${SFPI_VERSION}'"
		error "This may indicate an issue with the GitHub API responses."
		error_exit "Visit https://github.com/tenstorrent/tt-installer/wiki/Common-Problems#software-versions-are-empty-or-null for a fix."
	fi
}

# Function to check if Podman is installed
check_podman_installed() {
	command -v podman &> /dev/null
}

# Function to install Podman
install_podman() {
	log "Installing Podman"
	cd "${WORKDIR}"

	# Add GUIDs/UIDs for rootless Podman
	# See https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md
	${ROOT_CMD} usermod --add-subgids 10000-75535 "$(whoami)"
	${ROOT_CMD} usermod --add-subuids 10000-75535 "$(whoami)"

	# Install Podman using package manager
	case "${DISTRO_ID}" in
		"ubuntu"|"debian")
			${ROOT_CMD} apt install -y podman
			;;
		"fedora")
			${ROOT_CMD} dnf install -y podman
			;;
		"rhel"|"centos")
			${ROOT_CMD} dnf install -y podman
			;;
		"alpine")
			${ROOT_CMD} apk add podman
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
  --privileged \\
  --volume=/dev/hugepages-1G:/dev/hugepages-1G \\
  --volume=\${HOME}:/home/user \\
  --device=/dev/tenstorrent:/dev/tenstorrent \\
  --workdir=/home/user \\
  --env=DISPLAY=\${DISPLAY} \\
  --env=HOME=/home/user \\
  --env=TERM=\${TERM:-xterm-256color} \\
  --network=host \\
  --security-opt label=disable \\
  --entrypoint /bin/bash \\
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

# Install Podman Metalium "models" container
install_podman_metalium_models() {
	log "Installing Metalium Models Container via Podman"
	local PODMAN_METALIUM_MODELS_SCRIPT_DIR="${HOME}/.local/bin"
	local PODMAN_METALIUM_MODELS_SCRIPT_NAME="tt-metalium-models"
	local METALIUM_MODELS_IMAGE_TAG="latest-rc"
	local METALIUM_MODELS_IMAGE_URL="ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-release-models-amd64"

	# Create wrapper script directory
	mkdir -p "${PODMAN_METALIUM_MODELS_SCRIPT_DIR}" || error_exit "Failed to create script directory"

	# Create wrapper script
	log "Creating wrapper script..."
	cat > "${PODMAN_METALIUM_MODELS_SCRIPT_DIR}/${PODMAN_METALIUM_MODELS_SCRIPT_NAME}" << EOF
#!/bin/bash
# Wrapper script for tt-metalium-models using Podman

echo "================================================================================"
echo "NOTE: This container tool for tt-metalium is meant to enable users to try out"
echo "      demos, and is not meant for production use. This container is liable to"
echo "      to change at anytime."
echo ""
echo "      For more information see https://github.com/tenstorrent/tt-metal/issues/25602"
echo "================================================================================"

# Image configuration
METALIUM_IMAGE="${METALIUM_MODELS_IMAGE_URL}:${METALIUM_MODELS_IMAGE_TAG}"

# Run the command using Podman
#
# Explaining some changes:
#  removal of --volume=\${HOME}:/home/user \\: the user in the upstream monster
#  container is user, and we put the source code in that user's directory, so
#  this would override it
#
#  removal of --workdir=/home/user \\: not super needed, but it's nice for
#  people to just be in the source code, ready to go
#
#  addition of --entrypoint /bin/bash: The current upstream container needs to
#  override the entrypoint. Why not just corral users into /bin/bash?
podman run --rm -it \\
  --privileged \\
  --volume=/dev/hugepages-1G:/dev/hugepages-1G \\
  --device=/dev/tenstorrent:/dev/tenstorrent \\
  --env=DISPLAY=\${DISPLAY} \\
  --env=HOME=/home/user \\
  --env=TERM=\${TERM:-xterm-256color} \\
  --network=host \\
  --security-opt label=disable \\
  --entrypoint /bin/bash \\
  \${METALIUM_IMAGE} "\$@"
EOF

	# Make the script executable
	chmod +x "${PODMAN_METALIUM_MODELS_SCRIPT_DIR}/${PODMAN_METALIUM_MODELS_SCRIPT_NAME}" || error_exit "Failed to make script executable"

	# Check if the directory is in PATH
	if [[ ":${PATH}:" != *":${PODMAN_METALIUM_MODELS_SCRIPT_DIR}:"* ]]; then
		warn "${PODMAN_METALIUM_MODELS_SCRIPT_DIR} is not in your PATH."
		warn "A restart may fix this, or you may need to update your shell RC"
	fi

	# Pull the image
	log "Pulling the tt-metalium-models image (this may take a while)..."
	podman pull "${METALIUM_MODELS_IMAGE_URL}:${METALIUM_MODELS_IMAGE_TAG}" || error "Failed to pull image"

	log "Metalium Models installation completed"
	return 0
}

get_podman_metalium_choice() {
	# If we're on Ubuntu 20, Podman is not available - force disable
	if [[ "${IS_UBUNTU_20}" = "0" ]]; then
		_arg_install_metalium_container="off"
		_arg_install_metalium_models_container="off"
		_arg_install_podman="off"
		return
	fi
	# In non-interactive mode, use the provided arguments
	if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
		log "Non-interactive mode, using Podman Metalium installation preference: ${_arg_install_metalium_container}"
		log "Non-interactive mode, using Metalium Models installation preference: ${_arg_install_metalium_models_container}"
		return
	fi
	# Only ask if Podman is installed or will be installed
	if [[ "${_arg_install_podman}" = "on" ]] || check_podman_installed; then
		# Interactive mode - allow override
		log "Would you like to install the TT-Metalium slim container?"
		log "This container is appropriate if you only need to use TT-NN"
		if confirm "Install Metalium"; then
			_arg_install_metalium_container="on"
		else
			_arg_install_metalium_container="off"
		fi
	else
		# Podman won't be installed, so don't install Metalium
		_arg_install_metalium_container="off"
		warn "Podman is not and will not be installed, skipping Podman Metalium installation"
	fi
	# Only ask if Podman is installed or will be installed
	if [[ "${_arg_install_podman}" = "on" ]] || check_podman_installed; then
		# Interactive mode - allow override
		log "Would you like to install the TT-Metalium Model Demos container?"
		log "This container is best for users who need more TT-Metalium functionality, such as running prebuilt models, but it's large (8GB)"
		if confirm "Install Metalium Models"; then
			_arg_install_metalium_models_container="on"
		else
			_arg_install_metalium_models_container="off"
		fi
	else
		# Podman won't be installed, so don't install Metalium
		_arg_install_metalium_models_container="off"
		warn "Podman is not and will not be installed, skipping Podman Metalium Models installation"
	fi

	# Disable Podman if both Metalium containers are disabled
	if [[ "${_arg_install_metalium_container}" = "off" ]] && [[ "${_arg_install_metalium_models_container}" = "off" ]]; then
		_arg_install_podman="off"
	fi
}

manual_install_kmd() {
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
		# Ok so this gets exciting fast, so hang on for a second while I explain
		# During the offline installer we need to figure out what kernels are actually installed
		# because the kernel running on the system is not what we just installed and it's going
		# to complain up a storm if we don't have the headers for the running kernel, which we don't
		# so lets start by figuring out what kernels we do have (packaging, we can do this by doing a
		# ls on /lib/modules too but right now I'm doing it this way, deal.
		# Then we wander through and do dkms for the installed kernels only.  After that instead of
		# trying to modprobe the module on a system we might not have built for, we check if we match
		# and only then try modprobe
		for x in $( eval "${KERNEL_LISTING}" )
		do
			sudo dkms install "tenstorrent/${KMD_VERSION}" -k "${x}"
			if [[ "$( uname -r )" == "${x}" ]]
			then
				sudo modprobe tenstorrent
			fi
		done
	fi
}

manual_install_hugepages() {
	log "Setting up HugePages"
	BASE_TOOLS_URL="https://github.com/tenstorrent/tt-system-tools/releases/download"
	case "${DISTRO_ID}" in
		"ubuntu"|"debian")
			TOOLS_FILENAME="tenstorrent-tools_${SYSTOOLS_VERSION}_all.deb"
			TOOLS_URL="${BASE_TOOLS_URL}/v${SYSTOOLS_VERSION}/${TOOLS_FILENAME}"
			curl -fsSLO "${TOOLS_URL}"
			verify_download "${TOOLS_FILENAME}"
			sudo dpkg -i "${TOOLS_FILENAME}"
			if [[ "${SYSTEMD_NO}" != 0 ]]
			then
				sudo systemctl enable "${SYSTEMD_NOW}" tenstorrent-hugepages.service
				sudo systemctl enable "${SYSTEMD_NOW}" 'dev-hugepages\x2d1G.mount'
			fi
			;;
		"fedora"|"rhel"|"centos")
			TOOLS_FILENAME="tenstorrent-tools-${SYSTOOLS_VERSION}-1.noarch.rpm"
			TOOLS_URL="${BASE_TOOLS_URL}/v${SYSTOOLS_VERSION}/${TOOLS_FILENAME}"
			curl -fsSLO "${TOOLS_URL}"
			verify_download "${TOOLS_FILENAME}"
			sudo dnf install -y "${TOOLS_FILENAME}"
			if [[ "${SYSTEMD_NO}" != 0 ]]
			then
				sudo systemctl enable "${SYSTEMD_NOW}" tenstorrent-hugepages.service
				sudo systemctl enable "${SYSTEMD_NOW}" 'dev-hugepages\x2d1G.mount'
			fi
			;;
		*)
			error "This distro is unsupported. Skipping HugePages install!"
			;;
	esac
}

# Function to install SFPI
manual_install_sfpi() {
	log "Installing SFPI"
	local arch
	local SFPI_RELEASE_URL="https://github.com/tenstorrent/sfpi/releases/download"
	local SFPI_FILE_ARCH
	local SFPI_FILE_EXT
	local SFPI_FILE

	arch=$(uname -m)

	case "${arch}" in
		"aarch64"|"arm64")
			SFPI_FILE_ARCH="aarch64"
			;;
		"amd64"|"x86_64")
			SFPI_FILE_ARCH="x86_64"
			;;
		*)
			error "Unsupported architecture for SFPI installation: ${arch}"
			exit 1
			;;
	esac

	case "${DISTRO_ID}" in
		"debian"|"ubuntu")
			SFPI_FILE_EXT="deb"
			;;
		"centos"|"fedora"|"rhel")
			SFPI_FILE_EXT="rpm"
			;;
		"alpine")
			SFPI_FILE_EXT="apk"
			;;
		*)
			error "Unsupported distribution for SFPI installation: ${DISTRO_ID}"
			exit 1
			;;
	esac

	SFPI_FILE="sfpi_${SFPI_VERSION}_${SFPI_FILE_ARCH}.${SFPI_FILE_EXT}"
	log "Downloading ${SFPI_FILE}"

	curl -fsSLO "${SFPI_RELEASE_URL}/v${SFPI_VERSION}/${SFPI_FILE}"
	verify_download "${SFPI_FILE}"

	case "${SFPI_FILE_EXT}" in
		"deb")
			${ROOT_CMD} apt install -y "./${SFPI_FILE}"
			;;
		"rpm")
			${ROOT_CMD} dnf install -y "./${SFPI_FILE}"
			;;
		"apk")
			${ROOT_CMD} apk add "./${SFPI_FILE}"
			;;
		*)
			error "Unexpected SFPI package file extension: '${SFPI_FILE_EXT}'"
			exit 1
			;;
	esac
}

install_tt_repos () {
	log "Installing TT repositories to your distribution package manager"
	case "${DISTRO_ID}" in
		"ubuntu"|"debian")
			# Add the apt listing
			# shellcheck disable=2002
			echo "deb [signed-by=/etc/apt/keyrings/tt-pkg-key.asc] https://ppa.tenstorrent.com/ubuntu/ $( cat /etc/os-release | grep "^VERSION_CODENAME=" | sed 's/^VERSION_CODENAME=//' ) main" | sudo tee /etc/apt/sources.list.d/tenstorrent.list > /dev/null

			# Setup the keyring
			sudo mkdir -p /etc/apt/keyrings; sudo chmod 755 /etc/apt/keyrings

			# Download the key
			sudo wget -O /etc/apt/keyrings/tt-pkg-key.asc https://ppa.tenstorrent.com/ubuntu/tt-pkg-key.asc
			;;
		"fedora")
			error_exit "Cannot install TT repos on RPM distros just yet!"
			;;
		"rhel"|"centos")
			error_exit "Cannot install TT repos on RPM distros just yet!"
			;;
		*)
			error_exit "Unsupported distro: ${DISTRO_ID}"
			;;
	esac
}

install_sw_from_repos () {
	log "Installing software from TT repositories"
	case "${DISTRO_ID}" in
		"ubuntu"|"debian")
			# For now, install the big three
			sudo apt update
			sudo apt install -y tenstorrent-dkms tenstorrent-tools sfpi
			;;
		"fedora")
			error_exit "Cannot install from TT repos on RPM distros just yet!"
			;;
		"rhel"|"centos")
			error_exit "Cannot install from TT repos on RPM distros just yet!"
			;;
		*)
			error_exit "Unsupported distro: ${DISTRO_ID}"
			;;
	esac
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
	if [[ "${_arg_install_sfpi}" = "off" ]]; then
		warn "SFPI installation will be skipped"
	fi
	# shellcheck disable=SC2154
	if [[ "${_arg_install_tt_flash}" = "off" ]]; then
		warn "TT-Flash installation will be skipped"
	fi
	if [[ "${_arg_update_firmware}" = "off" ]]; then
		warn "Firmware update will be skipped"
	fi
	if [[ "${_arg_update_firmware}" = "force" ]]; then
		warn "Firmware will be forcibly updated"
	fi
	if [[ "${_arg_install_metalium_models_container}" = "on" ]]; then
		log "Metalium Models container will be installed"
	fi

	log "Checking for sudo permissions... (may request password)"
	check_has_sudo_perms

	# Check distribution and install base packages
	detect_distro
	log "Installing base packages"
	case "${DISTRO_ID}" in
		"ubuntu")
			${ROOT_CMD} apt update
			if [[ "${IS_UBUNTU_20}" = "0" ]]; then
				# On Ubuntu 20, install python3-venv and don't install pipx
				${ROOT_CMD} apt install -y git python3-pip python3-venv dkms cargo rustc jq
			else
				${ROOT_CMD} DEBIAN_FRONTEND=noninteractive apt install -y git python3-pip dkms cargo rustc pipx jq
			fi
			KERNEL_LISTING="${KERNEL_LISTING_UBUNTU}"
			;;
		"debian")
			# On Debian, packaged cargo and rustc are very old. Users must install them another way.
			${ROOT_CMD} apt update
			${ROOT_CMD} apt install -y git python3-pip dkms pipx jq
			KERNEL_LISTING="${KERNEL_LISTING_DEBIAN}"
			;;
		"fedora")
			${ROOT_CMD} dnf install -y git python3-pip python3-devel dkms cargo rust pipx jq
			KERNEL_LISTING="${KERNEL_LISTING_FEDORA}"
			;;
		"rhel"|"centos")
			${ROOT_CMD} dnf install -y epel-release
			${ROOT_CMD} dnf install -y git python3-pip python3-devel dkms cargo rust pipx jq
			KERNEL_LISTING="${KERNEL_LISTING_EL}"
			;;
		"alpine")
			${ROOT_CMD} apk add git py3-pip python3-dev akms cargo rust jq findutils shadow shadow-subids protoc maturin patchelf
			;;
		*)
			error "Unsupported distribution: ${DISTRO_ID}"
			exit 1
			;;
	esac

	if [[ "${IS_UBUNTU_20}" = "0" ]]; then
		warn "Ubuntu 20 is deprecated and support will be removed in a future release!"
		warn "Metalium installation will be unavailable. To install Metalium, upgrade to Ubuntu 22+"
		if [[ "${_arg_install_sfpi}" = "on" ]]; then
			warn "Pre-packaged SFPI is unavailable for Ubuntu 20; disabling"
			_arg_install_sfpi="off"
		fi
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
		echo "HAVE_SET_TT_SW_VERSIONS: ${HAVE_SET_TT_SW_VERSIONS}"

		which jq > /dev/null 2>&1
		res=$?
		if [[ "${res}" == "0" ]]
		then
			error_exit "Cannot fetch versions of TT software, likely a transient error in getting the versions - please try again"
		else
			error_exit "Cannot fetch versions of TT software. Is jq installed?"
		fi
	fi

	# Get Podman Metalium installation choice
	get_podman_metalium_choice

	# Python package installation preference
	get_python_choice

	# Enforce restrictions on Ubuntu 20
	if [[ "${IS_UBUNTU_20}" = "0" ]] && [[ "${PYTHON_CHOICE}" = "pipx" ]]; then
		warn "pipx installation not supported on Ubuntu 20, defaulting to virtual environment"
		PYTHON_CHOICE="new-venv"
	fi

	# Set up Python environment based on choice
	case ${PYTHON_CHOICE} in
		"active-venv")
			if [[ -z "${VIRTUAL_ENV:-}" ]]; then
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
			pipx ensurepath "${PIPX_ENSUREPATH_EXTRAS}"
			# Enable the pipx path in this shell session
			export PATH="${PATH}:${HOME}/.local/bin/"
			INSTALLED_IN_VENV=1
			PYTHON_INSTALL_CMD="pipx install ${PIPX_INSTALL_EXTRAS}"
			;;
		"new-venv"|*)
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
				case "${DISTRO_ID}" in
					"alpine")
						${ROOT_CMD} akms uninstall tenstorrent
						git clone --branch "ttkmd-${KMD_VERSION}" "https://github.com/${TT_KMD_GH_REPO}"
						cd tt-kmd
						${ROOT_CMD} akms install .
						${ROOT_CMD} modprobe tenstorrent
						;;
					*)
						${ROOT_CMD} dkms remove "tenstorrent/${KMD_INSTALLED_VERSION}" --all
						git clone --branch "ttkmd-${KMD_VERSION}" "https://github.com/${TT_KMD_GH_REPO}"
						${ROOT_CMD} dkms add tt-kmd
						${ROOT_CMD} dkms install "tenstorrent/${KMD_VERSION}"
						${ROOT_CMD} modprobe tenstorrent
						;;
				esac
			else
				warn "Skipping KMD installation"
			fi
		else
			# Only install KMD if it's not already installed
			git clone --branch "ttkmd-${KMD_VERSION}" https://github.com/tenstorrent/tt-kmd.git
			case "${DISTRO_ID}" in
				"alpine")	
					cd tt-kmd
					${ROOT_CMD} akms install .
					${ROOT_CMD} modprobe tenstorrent
					;;
				*)
					${ROOT_CMD} dkms add tt-kmd
			# Ok so this gets exciting fast, so hang on for a second while I explain
			# During the offline installer we need to figure out what kernels are actually installed
			# because the kernel running on the system is not what we just installed and it's going
			# to complain up a storm if we don't have the headers for the running kernel, which we don't
			# so lets start by figuring out what kernels we do have (packaging, we can do this by doing a
			# ls on /lib/modules too but right now I'm doing it this way, deal.
			# Then we wander through and do dkms for the installed kernels only.  After that instead of
			# trying to modprobe the module on a system we might not have built for, we check if we match
			# and only then try modprobe
			for x in $( eval "${KERNEL_LISTING}" )
			do
				${ROOT_CMD} dkms install "tenstorrent/${KMD_VERSION}" -k "${x}"
				if [[ "$( uname -r )" == "${x}" ]]
				then
					${ROOT_CMD} modprobe tenstorrent
				fi
			done
					;;
			esac
		fi
		manual_install_kmd
	fi

	# Install TT-Flash and Firmware
	# Skip tt-flash installation if flag is set
	if [[ "${_arg_install_tt_flash}" = "off" ]]; then
		log "Skipping TT-Flash installation"
	else
		log "Installing TT-Flash"
		cd "${WORKDIR}"
		${PYTHON_INSTALL_CMD} git+https://github.com/tenstorrent/tt-flash.git@"${FLASH_VERSION}"
	fi

	if [[ "${_arg_update_firmware}" = "off" ]]; then
		log "Skipping firmware update"
	else
		log "Updating firmware"
		# Create FW_FILE based on FW_VERSION
		FW_FILE="fw_pack-${FW_VERSION}.fwbundle"
		FW_RELEASE_URL="https://github.com/tenstorrent/tt-firmware/releases/download"
		BACKUP_FW_RELEASE_URL="https://github.com/tenstorrent/tt-zephyr-platforms/releases/download"

		# Download from GitHub releases
		if ! curl -fsSLO "${FW_RELEASE_URL}/v${FW_VERSION}/${FW_FILE}"; then
			warn "Could not find firmware bundle at main URL- trying backup URL"
			if ! curl -fsSLO "${BACKUP_FW_RELEASE_URL}/v${FW_VERSION}/${FW_FILE}"; then
				error_exit "Could not download firmware bundle. Ensure firmware version is valid."
			fi
		fi

		verify_download "${FW_FILE}"

		if [[ "${_arg_update_firmware}" = "force" ]]; then
			tt-flash --fw-tar "${FW_FILE}" --force
		else
			tt-flash --fw-tar "${FW_FILE}"
		fi
	fi

	# shellcheck disable=SC2154
	if [[ "${_arg_install_tt_topology}" = "on" ]]; then
		log "Installing tt-topology"

		if [[ -n "${TT_TOPOLOGY_VERSION:-}" ]]; then
			TOPOLOGY_VERSION="${TT_TOPOLOGY_VERSION}"
		elif [[ -n "${_arg_topology_version}" ]]; then
			TOPOLOGY_VERSION="${_arg_topology_version}"
		else
			if TOPOLOGY_VERSION=$(fetch_latest_version "${TT_TOPOLOGY_GH_REPO}"); then
				: # Success, TOPOLOGY_VERSION is set
			else
				local topology_exit_code=$?
				handle_version_fetch_error "tt-topology" "${topology_exit_code}" "${TT_TOPOLOGY_GH_REPO}"
				error_exit "Failed to fetch tt-topology version. Installation cannot continue."
			fi
		fi

		log "Topology Version: ${TOPOLOGY_VERSION}"

		${PYTHON_INSTALL_CMD} git+https://github.com/tenstorrent/tt-topology.git@"${TOPOLOGY_VERSION}"
	fi

	# Setup HugePages
	# Skip HugePages installation if flag is set
	if [[ "${_arg_install_hugepages}" = "off" ]]; then
		warn "Skipping HugePages setup"
	else
		log "Setting up HugePages"
		case "${DISTRO_ID}" in
			"ubuntu"|"debian")
				TOOLS_FILENAME="tenstorrent-tools_${SYSTOOLS_VERSION}_all.deb"
				TOOLS_URL="${BASE_TOOLS_URL}/v${SYSTOOLS_VERSION}/${TOOLS_FILENAME}"
				curl -fsSLO "${TOOLS_URL}"
				verify_download "${TOOLS_FILENAME}"
				sudo dpkg -i "${TOOLS_FILENAME}"
				if [[ "${SYSTEMD_NO}" != 0 ]]
				then
					${ROOT_CMD} systemctl enable "${SYSTEMD_NOW}" tenstorrent-hugepages.service
					${ROOT_CMD} systemctl enable "${SYSTEMD_NOW}" 'dev-hugepages\x2d1G.mount'
				fi
				;;
			"fedora"|"rhel"|"centos")
				TOOLS_FILENAME="tenstorrent-tools-${SYSTOOLS_VERSION}-1.noarch.rpm"
				TOOLS_URL="${BASE_TOOLS_URL}/v${SYSTOOLS_VERSION}/${TOOLS_FILENAME}"
				curl -fsSLO "${TOOLS_URL}"
				verify_download "${TOOLS_FILENAME}"
				${ROOT_CMD} dnf install -y "${TOOLS_FILENAME}"
				if [[ "${SYSTEMD_NO}" != 0 ]]
				then
					${ROOT_CMD} systemctl enable "${SYSTEMD_NOW}" tenstorrent-hugepages.service
					${ROOT_CMD} systemctl enable "${SYSTEMD_NOW}" 'dev-hugepages\x2d1G.mount'
				fi
				;;
			"alpine")
				TOOLS_FILENAME="tt-system-tools-${SYSTOOLS_VERSION}-r0.apk"
				TOOLS_URL="https://github.com/tenstorrent/tt-system-tools/releases/download/v${SYSTOOLS_VERSION}/${TOOLS_FILENAME}"
				curl -fsSLO "${TOOLS_URL}"
				verify_download "${TOOLS_FILENAME}"
				${ROOT_CMD} apk add "${TOOLS_FILENAME}" --allow-untrusted
				${ROOT_CMD} rc-update add tenstorrent-hugepages
				${ROOT_CMD} rc-update add tenstorrent-mount-hugepages
				${ROOT_CMD} rc-service tenstorrent-hugepages start
				${ROOT_CMD} rc-service tenstorrent-mount-hugepages start
				;;
			*)
				error "This distro is unsupported. Skipping HugePages install!"
				;;
		esac
		manual_install_hugepages
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

	# Install Metalium Models container if requested
	if [[ "${_arg_install_metalium_models_container}" = "on" ]]; then
		if ! check_podman_installed; then
			warn "Podman is not installed. Cannot install Metalium Models."
		else
			install_podman_metalium_models
		fi
	fi

	if [[ ${INSTALL_TT_REPOS:-} = "on" ]]; then
		install_tt_repos
	fi

	if [[ ${INSTALL_SW_FROM_REPOS:-} = "on" ]]; then
		install_sw_from_repos
	fi

	if [[ "${_arg_install_sfpi}" = "on" ]]; then
		manual_install_sfpi
	fi

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

	# Log successful completion message
	log "✅ Installation completed successfully."
	log "Installation log saved to: ${LOG_FILE}"

	# Auto-reboot if specified
	if [[ "${REBOOT_OPTION}" = "always" ]]; then
		log "Auto-reboot enabled. Rebooting now..."
		${ROOT_CMD} reboot
	# Otherwise, ask if specified
	elif [[ "${REBOOT_OPTION}" = "ask" ]]; then
		if confirm "Would you like to reboot now?"; then
			log "Rebooting..."
			${ROOT_CMD} reboot
		fi
	fi
}

# Start installation
main

# ] <-- needed because of Argbash

# vim: noai:ts=4:sw=4:ft=bash
