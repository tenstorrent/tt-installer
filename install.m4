#!/bin/bash
# shellcheck disable=SC2317
# shellcheck disable=SC2154

# SPDX-FileCopyrightText: © 2026 Tenstorrent AI ULC
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
# ARG_OPTIONAL_SINGLE([install-container-runtime],,[Container runtime to install: auto (install Docker unless a runtime is already present), podman, docker, none],[auto])
# ARG_OPTIONAL_BOOLEAN([install-metalium-container],,[Download and install Metalium container],[on])
# ARG_OPTIONAL_BOOLEAN([install-forge-container],,[Download and install Forge container],[off])
# ARG_OPTIONAL_BOOLEAN([install-tt-flash],,[Install tt-flash for updating device firmware],[on])
# ARG_OPTIONAL_BOOLEAN([install-tt-smi],,[Install tt-smi for device monitoring],[on])
# ARG_OPTIONAL_BOOLEAN([install-tt-topology],,[Install tt-topology (Wormhole only)],[off])
# ARG_OPTIONAL_BOOLEAN([install-sfpi],,[Install SFPI],[on])
# ARG_OPTIONAL_BOOLEAN([install-inference-server],,[Install tt-inference-server],[on])
# ARG_OPTIONAL_BOOLEAN([install-studio],,[Install tt-studio],[on])
# ARG_OPTIONAL_BOOLEAN([pull-container-images],,[Pre-pull container images (Metalium/Forge) during install; if off (default), the wrapper scripts pull on first run instead],[off])

# =========================  Metalium Container Arguments =========================
# ARG_OPTIONAL_SINGLE([metalium-image-url],,[Container image URL to pull/run],[ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-release-amd64])
# ARG_OPTIONAL_SINGLE([metalium-image-tag],,[Tag (version) of the Metalium image],[latest-rc])
# ARG_OPTIONAL_SINGLE([metalium-container-script-dir],,[Directory where the helper wrapper will be written],["$HOME/.local/bin"])
# ARG_OPTIONAL_SINGLE([metalium-container-script-name],,[Name of the helper wrapper script],["tt-metalium"])
# ARG_OPTIONAL_BOOLEAN([install-metalium-models-container],,[Install additional TT-Metalium container for running model demos],[off])

# =========================  Forge Container Arguments =========================
# ARG_OPTIONAL_SINGLE([forge-image-url],,[Container image URL to pull/run],[ghcr.io/tenstorrent/tt-xla-slim])
# ARG_OPTIONAL_SINGLE([forge-image-tag],,[Tag (version) of the Forge image],[latest])
# ARG_OPTIONAL_SINGLE([forge-container-script-dir],,[Directory where the helper wrapper will be written],["$HOME/.local/bin"])
# ARG_OPTIONAL_SINGLE([forge-container-script-name],,[Name of the helper wrapper script],["tt-forge"])

# ========================= String Arguments =========================
# ARG_OPTIONAL_SINGLE([python-choice],,[Python setup strategy: active-venv, new-venv, system-python, pipx],[new-venv])
# ARG_OPTIONAL_BOOLEAN([use-uv],,[Use uv instead of pip for Python package installation],[on])
# ARG_OPTIONAL_SINGLE([python-version],,[Python version for a new venv (e.g. 3.12); requires --use-uv, which provisions it via uv],[3.12])
# ARG_OPTIONAL_SINGLE([reboot-option],,[Reboot policy after install: ask, never, always],[ask])
# ARG_OPTIONAL_SINGLE([update-firmware],,[Update TT device firmware: on, off, force],[force])
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

# ========================= State File Arguments =========================
# ARG_OPTIONAL_SINGLE([versions],,[Version channel: 'release' (pin to golden versions baked into this release), 'rolling' (latest of everything), or a path to a .ttis file (full non-interactive import)],[release])
# ARG_OPTIONAL_SINGLE([export-schema],,[(Developer/CI) Export installer state to .ttis file after installation],[])


# ========================= Mode Arguments =========================
# ARG_OPTIONAL_BOOLEAN([mode-container],,[Enable container mode (skips KMD, HugePages, and SFPI, never reboots)],[off])
# ARG_OPTIONAL_BOOLEAN([mode-non-interactive],,[Enable non-interactive mode (no user prompts)],[off])
# ARG_OPTIONAL_BOOLEAN([dry-run],,[Preview the installation plan without executing mutations],[off])
# ARG_OPTIONAL_BOOLEAN([verbose],,[Enable verbose output for debugging])

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

# Backward compatibility: --install-container-runtime once used "no"; it is
# now "none" to match the syntax of other arguments.
if [[ "${_arg_install_container_runtime}" = "no" ]]; then
	_arg_install_container_runtime="none"
fi

# If container mode is enabled, disable KMD, HugePages, SFPI, and firmware
# updates -- none of these are host-oriented actions a container should take
# shellcheck disable=SC2154
if [[ "${_arg_mode_container}" = "on" ]]; then
	_arg_install_kmd="off"
	_arg_install_hugepages="off" # Both KMD and HugePages must live on the host kernel
	_arg_install_container_runtime="none" # No container runtime in container
	_arg_install_sfpi="off"
	_arg_reboot_option="never" # Do not reboot
	_arg_update_firmware="off" # Firmware lives on the host, not the container
fi

PIPX_ENSUREPATH_EXTRAS="${TT_PIPX_ENSUREPATH_EXTRAS:- }"
PIPX_INSTALL_EXTRAS="${TT_PIPX_INSTALL_EXTRAS:- }"

# ========================= Main Script =========================

# A source-only load is used by the unit tests. It must not create a temporary
# directory, redirect the caller's file descriptors, or invoke main.
INSTALLER_SOURCE_ONLY="${INSTALLER_SOURCE_ONLY:-0}"
if [[ "${INSTALLER_SOURCE_ONLY}" = "1" && "${BASH_SOURCE[0]}" = "$0" ]]; then
	printf '%s\n' "INSTALLER_SOURCE_ONLY is only valid when sourcing install.sh" >&2
	exit 2
fi
if [[ "${INSTALLER_SOURCE_ONLY}" = "1" ]]; then
	WORKDIR="${TMPDIR:-/tmp}/tt-installer-source"
	LOG_FILE="/dev/null"
else
	# Create working directory
	TMP_DIR_TEMPLATE="tenstorrent_install_XXXXXX"
	WORKDIR=$(mktemp -d -p "${TMPDIR:-/tmp}" "${TMP_DIR_TEMPLATE}")

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
	cleanup_dry_run_workdir() {
		if [[ "${_arg_dry_run:-off}" = "on" ]]; then
			rm -rf -- "${WORKDIR}"
		fi
	}
	trap cleanup_dry_run_workdir EXIT
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Pinned installer-golden-versions release tag. Bump here to adopt a new golden
# matrix; the Golden Matrix CI workflow reads this value out of install.m4.
readonly TTIS_GOLDEN_VERSIONS_TAG="v1.0.0"
readonly METALIUM_MODELS_IMAGE_URL="ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-release-models-amd64"
readonly METALIUM_MODELS_IMAGE_TAG="latest-rc"

# Pinned uv release and the SHA-256 of that release's uv-installer.sh. The
# installer script is verified against this hash before it runs (it in turn
# verifies the uv binary against its own embedded checksums), so both values
# must move together. Bump with `make bump-uv`, which cross-checks the hash
# from two origins and refuses non-immutable upstream releases.
readonly UV_VERSION="0.12.5"
readonly UV_INSTALLER_SHA256="504511fbbbd811aeaba6738abc79408956b6c7da0ca35437b3dcc24a41efc111"

# ttis.sh is inlined here at build time (see scripts/inline-ttis.sh), replacing
# the placeholder line below with the body of ttis.sh between its TTIS_INLINE
# markers. This keeps the released install.sh a single self-contained file so it
# runs via `bash -c "$(curl ... install.sh)"` with no second file to fetch.
# ttis.sh provides TTIS_PACKAGE_MAP (used to build package_registry) and the
# ttis_* functions used by --versions / --export-schema.
# __TTIS_INLINE__

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

# Seconds apt-get waits for the dpkg lock before giving up. Ubuntu's
# unattended-upgrades or the apt daily timer can hold the lock when we run.
APT_LOCK_TIMEOUT=120

# Wrapper for all apt-get invocations:
# - Waits up to APT_LOCK_TIMEOUT seconds for the dpkg lock instead of aborting
#   immediately, and explains what to do if the wait still times out.
# - Allows downgrades on install, needed when pinned versions (the 'release'
#   channel or an imported .ttis file) are older than what is installed.
apt_get() {
	local apt_status=0
	local apt_log="${WORKDIR}/apt-last-run.log"
	local apt_opts=("-o" "DPkg::Lock::Timeout=${APT_LOCK_TIMEOUT}")
	if [[ "${1:-}" == "install" ]]; then
		apt_opts+=("--allow-downgrades")
	fi
	# 2>&1 keeps apt's errors in the tee'd log so we can detect a lock timeout
	sudo DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" "$@" 2>&1 | tee "${apt_log}" || apt_status=$?
	if [[ "${apt_status}" -ne 0 ]] && grep -Eq "Could not get lock|Unable to acquire the dpkg" "${apt_log}"; then
		error "apt-get could not acquire the dpkg lock after waiting ${APT_LOCK_TIMEOUT} seconds."
		error "Another package manager process is holding it — usually Ubuntu's unattended-upgrades or the apt daily timer."
		error "See what holds the lock with: sudo fuser -v /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock"
		error "Wait for it to finish (or stop it with 'sudo systemctl stop unattended-upgrades'), then re-run this installer."
	fi
	return "${apt_status}"
}

detect_distro() {
	# shellcheck disable=SC1091 # Always present
local os_release_file="${TT_INSTALLER_OS_RELEASE:-/etc/os-release}"
	if [[ -f "${os_release_file}" ]]; then
		# shellcheck source=/etc/os-release
		. "${os_release_file}"
		DISTRO_ID=${ID}
		case ${DISTRO_ID} in
			ubuntu|debian|fedora|rhel|centos)
				;; # It's a known distro, do nothing.
			*)
				# Could be a derivative distribution, check ID_LIKE
				if [[ -n "${ID_LIKE:-}" ]]; then
					# ID_LIKE can be a space-separated list. Check each of them.
					for id_like_distro in ${ID_LIKE}; do
						case ${id_like_distro} in
							ubuntu|debian|fedora|rhel)
								DISTRO_ID=${id_like_distro}
								break # Use the first one found.
								;;
						esac
					done
				fi
				;;
		esac
		# Set package manager based on distribution
		case "${DISTRO_ID}" in
			"ubuntu"|"debian")
				PKG_MANAGER="apt-get"
				;;
			"fedora"|"rhel"|"centos")
				PKG_MANAGER="dnf"
				;;
			*)
				error "Unsupported distribution: ${DISTRO_ID}"
				exit 1
				;;
		esac
	else
		error "Cannot detect Linux distribution"
		exit 1
	fi
}

# Normalize and validate option values before any operation can be selected.
# This function intentionally only changes _arg_* values and returns an error.
normalize_options() {
	case "${_arg_install_container_runtime}" in
		no) _arg_install_container_runtime="none" ;;
		auto|podman|docker|none) ;;
		*) error "Invalid container runtime option: ${_arg_install_container_runtime}"; return 1 ;;
	esac
	case "${_arg_update_firmware}" in
		on|off|force) ;;
		*) error "Invalid firmware option: ${_arg_update_firmware}"; return 1 ;;
	esac
	case "${_arg_python_choice}" in
		active-venv|new-venv|system-python|pipx) ;;
		*) error "Invalid Python strategy: ${_arg_python_choice}"; return 1 ;;
	esac
	case "${_arg_reboot_option}" in
		ask|never|always) ;;
		*) error "Invalid reboot option: ${_arg_reboot_option}"; return 1 ;;
	esac

	if [[ "${_arg_mode_container}" = "on" ]]; then
		_arg_install_kmd="off"
		_arg_install_hugepages="off"
		_arg_install_container_runtime="none"
		_arg_install_sfpi="off"
		_arg_reboot_option="never"
	fi
}

# Resolve the distro-specific base package set without installing anything.
resolve_base_packages() {
	BASE_BOOTSTRAP_PACKAGES=()
	BASE_SYSTEM_PACKAGES=()
	case "${DISTRO_ID}" in
		ubuntu)
			if version_at_least "${VERSION_ID:-0}" 24.04; then
				# rustup is packaged from noble on and conflicts with cargo/rustc, so it replaces them.
				BASE_SYSTEM_PACKAGES=(git python3-pip dkms rustup pipx jq protobuf-compiler)
			else
				BASE_SYSTEM_PACKAGES=(git python3-pip dkms cargo rustc pipx jq protobuf-compiler)
			fi
			;;
		debian)
			if version_at_least "${VERSION_ID:-0}" 13; then
				# From trixie on, rustup is packaged (and conflicts with the very old cargo/rustc).
				BASE_SYSTEM_PACKAGES=(git python3-pip dkms rustup pipx jq protobuf-compiler)
			else
				# On older Debian, packaged cargo and rustc are very old. Users must install them another way.
				BASE_SYSTEM_PACKAGES=(git python3-pip dkms pipx jq protobuf-compiler)
			fi
			;;
		fedora)
			BASE_SYSTEM_PACKAGES=(git python3-pip python3-devel dkms cargo rust pipx jq protobuf-compiler) ;;
		rhel|centos)
			BASE_BOOTSTRAP_PACKAGES=(epel-release)
			BASE_SYSTEM_PACKAGES=(git python3-pip python3-devel dkms cargo rust pipx jq protobuf-compiler) ;;
		*) error "Unsupported distribution: ${DISTRO_ID}"; return 1 ;;
	esac
}

# Build the package registry from the single package map and imported extras.
build_package_registry() {
	declare -gA package_registry=()
	local entry pkg type install_var version_var
	for entry in "${TTIS_PACKAGE_MAP[@]}"; do
		IFS='|' read -r pkg type install_var version_var <<< "${entry}"
		package_registry["${pkg}"]="${pkg}|${!install_var}|${!version_var}|${type}"
	done
	for entry in "${TTIS_IMPORTED_PACKAGES[@]+${TTIS_IMPORTED_PACKAGES[@]}}"; do
		IFS='|' read -r pkg install_var version type <<< "${entry}"
		package_registry["${pkg}"]="${pkg}|${install_var}|${version}|${type}"
	done
}

# Convert the registry into package-manager and Python action lists. This is a
# formatting step only; package managers are invoked later by main.
resolve_package_actions() {
	SYSTEM_PACKAGES=()
	PYTHON_PACKAGES=()
	local key pkg install_flag version type
	for key in "${!package_registry[@]}"; do
		IFS='|' read -r pkg install_flag version type <<< "${package_registry[${key}]}"
		[[ "${install_flag}" = "on" ]] || continue
		case "${type}" in
			system)
				if [[ -z "${version}" ]]; then
					SYSTEM_PACKAGES+=("${pkg}")
				elif [[ "${PKG_MANAGER}" = "apt-get" ]]; then
					SYSTEM_PACKAGES+=("${pkg}=${version}")
				elif [[ "${PKG_MANAGER}" = "dnf" ]]; then
					SYSTEM_PACKAGES+=("${pkg}-${version}")
				else
					SYSTEM_PACKAGES+=("${pkg}")
				fi
				;;
			python)
				if [[ -z "${version}" ]]; then
					PYTHON_PACKAGES+=("${pkg}")
				else
					PYTHON_PACKAGES+=("${pkg}==${version}")
				fi
				;;
		esac
	done
	if [[ ${#SYSTEM_PACKAGES[@]} -gt 0 ]]; then
		mapfile -t SYSTEM_PACKAGES < <(printf '%s\n' "${SYSTEM_PACKAGES[@]}" | LC_ALL=C sort)
	fi
	if [[ ${#PYTHON_PACKAGES[@]} -gt 0 ]]; then
		mapfile -t PYTHON_PACKAGES < <(printf '%s\n' "${PYTHON_PACKAGES[@]}" | LC_ALL=C sort)
	fi
}

disable_unused_container_runtime() {
	if [[ "${_arg_install_metalium_container}" = "off" \
		&& "${_arg_install_metalium_models_container}" = "off" \
		&& "${_arg_install_forge_container}" = "off" ]]; then
		_arg_install_container_runtime="none"
	fi
}

# Resolve the requested runtime using read-only command discovery only.
resolve_container_runtime() {
	RESOLVED_CONTAINER_RUNTIME="${_arg_install_container_runtime}"
	CONTAINER_RUNTIME_PRESENT=0
	CONTAINER_PULL_PREFIX=""
	CONTAINER_CLI=""
	if [[ "${RESOLVED_CONTAINER_RUNTIME}" = "auto" ]]; then
		if command -v docker >/dev/null 2>&1; then
			local docker_version
			docker_version=$(docker --version 2>/dev/null || true)
			if [[ "${docker_version,,}" == *podman* ]]; then
				RESOLVED_CONTAINER_RUNTIME="podman"
			else
				RESOLVED_CONTAINER_RUNTIME="docker"
			fi
			CONTAINER_RUNTIME_PRESENT=1
		elif command -v podman >/dev/null 2>&1; then
			RESOLVED_CONTAINER_RUNTIME="podman"
			CONTAINER_RUNTIME_PRESENT=1
		else
			RESOLVED_CONTAINER_RUNTIME="docker"
		fi
	elif command -v "${RESOLVED_CONTAINER_RUNTIME}" >/dev/null 2>&1; then
		CONTAINER_RUNTIME_PRESENT=1
	fi
	case "${RESOLVED_CONTAINER_RUNTIME}" in
		docker) CONTAINER_CLI="docker" ;;
		podman) CONTAINER_CLI="podman" ;;
		none)
			if command -v docker >/dev/null 2>&1; then
				local docker_version
				docker_version=$(docker --version 2>/dev/null || true)
				if [[ "${docker_version,,}" == *podman* ]]; then
					CONTAINER_CLI="podman"
				else
					CONTAINER_CLI="docker"
				fi
				CONTAINER_RUNTIME_PRESENT=1
			elif command -v podman >/dev/null 2>&1; then
				CONTAINER_CLI="podman"
				CONTAINER_RUNTIME_PRESENT=1
			fi
			;;
	esac
	if [[ "${CONTAINER_CLI}" = "docker" && "${CONTAINER_RUNTIME_PRESENT}" = "1" ]]; then
		if ! docker info >/dev/null 2>&1; then CONTAINER_PULL_PREFIX="sudo"; fi
	fi
}

# Resolve firmware policy independently from firmware download/flash actions.
resolve_firmware_action() {
	case "${_arg_update_firmware}" in
		off) RESOLVED_FIRMWARE_ACTION="skip" ;;
		on) RESOLVED_FIRMWARE_ACTION="update" ;;
		force) RESOLVED_FIRMWARE_ACTION="force-flash" ;;
		*) error "Invalid firmware option: ${_arg_update_firmware}"; return 1 ;;
	esac
}

render_install_plan() {
	local arch="${TT_INSTALLER_ARCH:-$(uname -m)}"
	local kernel="${TT_INSTALLER_KERNEL:-$(uname -r)}"
	local metalium_image_action="disabled"
	local models_image_action="disabled"
	local forge_image_action="disabled"
	if [[ "${_arg_install_metalium_container}" = "on" ]]; then
		metalium_image_action="deferred until first wrapper run"
		[[ "${_arg_pull_container_images}" = "on" ]] && metalium_image_action="pull during install"
	fi
	if [[ "${_arg_install_metalium_models_container}" = "on" ]]; then
		models_image_action="deferred until first wrapper run"
		[[ "${_arg_pull_container_images}" = "on" ]] && models_image_action="pull during install"
	fi
	if [[ "${_arg_install_forge_container}" = "on" ]]; then
		forge_image_action="deferred until first wrapper run"
		[[ "${_arg_pull_container_images}" = "on" ]] && forge_image_action="pull during install"
	fi
	if [[ -z "${CONTAINER_CLI}" ]]; then
		metalium_image_action="disabled"
		models_image_action="disabled"
		forge_image_action="disabled"
	fi
	echo -e "${YELLOW}==== DRY-RUN: Installation Preview ====${NC}"
	echo "Action execution: suppressed"
	echo "Platform: ${DISTRO_ID} ${VERSION_ID:-unknown} (${PKG_MANAGER})"
	echo "Architecture: ${arch}"
	echo "Kernel: ${kernel}"
	echo "Bootstrap packages: ${BASE_BOOTSTRAP_PACKAGES[*]:-none}"
	echo "System packages: ${BASE_SYSTEM_PACKAGES[*]}"
	echo "TT system packages: ${SYSTEM_PACKAGES[*]:-none}"
	echo "Python packages: ${PYTHON_PACKAGES[*]:-none}"
	echo "HugePages: ${_arg_install_hugepages}"
	echo "Firmware: ${RESOLVED_FIRMWARE_ACTION} ${_arg_fw_version:-latest}"
	echo "Privileged operations: suppressed (sudo, package manager, DKMS, modprobe, tt-flash, reboot)"
	echo "Containers: runtime=${RESOLVED_CONTAINER_RUNTIME} present=${CONTAINER_RUNTIME_PRESENT} command=${CONTAINER_CLI:-none}"
	echo "Metalium image: ${_arg_metalium_image_url}:${_arg_metalium_image_tag} (${metalium_image_action})"
	echo "Metalium Models image: ${METALIUM_MODELS_IMAGE_URL}:${METALIUM_MODELS_IMAGE_TAG} (${models_image_action})"
	echo "Forge image: ${_arg_forge_image_url}:${_arg_forge_image_tag} (${forge_image_action})"
	echo "Inference Server: ${_arg_install_inference_server}"
	echo "Studio: ${_arg_install_studio}"
	echo "Python strategy: ${_arg_python_choice}"
	echo "Reboot: suppressed (${_arg_reboot_option})"
	echo "Export: suppressed${_arg_export_schema:+ (${_arg_export_schema})}"
}

# True when dotted version ${1} (e.g. VERSION_ID "24.04" or "13") is at least ${2}.
version_at_least() {
	[[ "$(printf '%s\n%s\n' "${2}" "${1}" | sort -V | head -n 1)" = "${2}" ]]
}

# Fetch the golden .ttis schema for this distro from the pinned
# tt-sw-manifest release. The release publishes one asset per
# distro/version named "<distro_id>-<version_id>.ttis", so we download that file
# directly. On success, sets GOLDEN_SCHEMA_FILE to its path and returns 0.
# Returns non-zero (with a warning) if no matching asset exists (HTTP error) —
# callers fall back to rolling versions. Requires detect_distro to have run.
fetch_golden_schema() {
	local asset="${DISTRO_ID}-${VERSION_ID}.ttis"
	local dest="${WORKDIR}/${asset}"
	local url="https://github.com/tenstorrent/tt-sw-manifest/releases/download/${TTIS_GOLDEN_VERSIONS_TAG}/${asset}"

	if ! curl -fsSL "${url}" -o "${dest}"; then
		warn "No golden versions file for ${DISTRO_ID} ${VERSION_ID} in release ${TTIS_GOLDEN_VERSIONS_TAG}"
		return 1
	fi

	GOLDEN_SCHEMA_FILE="${dest}"
	return 0
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

set_non_interactive_defaults() {
	if [[ "${_arg_mode_non_interactive}" = "on" ]] && [[ "${_arg_reboot_option}" = "ask" ]]; then
		_arg_reboot_option="never" # Do not reboot in non-interactive mode
	fi
}

# True when the user explicitly passed the given option on the command line
# (matches both "--opt" and "--opt=value" forms). Used to decide whether to
# announce settings that happen to match the installer's defaults.
arg_was_passed() {
	local opt="$1" arg
	for arg in "${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}"; do
		if [[ "${arg}" == "${opt}" || "${arg}" == "${opt}="* ]]; then
			return 0
		fi
	done
	return 1
}

maybe_enable_default_mode() {
	# Respect already-set non-interactive mode
	if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
		return
	fi

	log "Would you like to proceed with the default installation?"
	log "Selecting yes enables non-interactive mode and continues with default options."
	if confirm "Proceed with default installation (recommended for most users)"; then
		_arg_mode_non_interactive="on"
		set_non_interactive_defaults
		log "Default installation selected. Continuing in non-interactive mode."
	fi
}

# Function to check if uv is installed
check_uv_installed() {
	command -v uv &> /dev/null
}

# Install uv (used when --use-uv is set but uv is not already present).
# Fetches the pinned release's installer from GitHub (astral.sh is unreachable
# from some networks, e.g. returns 403 behind restrictive egress) and verifies
# it against UV_INSTALLER_SHA256 before running it; the installer then verifies
# the uv binary against its own embedded checksums. A failed download falls
# back to the same pinned version from PyPI via pipx (already a base package);
# a hash mismatch means the script is not the one we pinned and is always a
# hard error, never a fallback. Both paths install uv into ~/.local/bin.
install_uv() {
	log "Installing uv ${UV_VERSION}"
	local uv_installer="${WORKDIR}/uv-installer.sh"
	if curl -fsSL -o "${uv_installer}" \
		"https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-installer.sh"; then
		echo "${UV_INSTALLER_SHA256}  ${uv_installer}" | sha256sum --check --quiet - \
			|| error_exit "uv installer failed SHA-256 verification (expected ${UV_INSTALLER_SHA256}); refusing to run it"
		sh "${uv_installer}"
	else
		warn "Could not download the uv installer from GitHub, installing uv ${UV_VERSION} from PyPI with pipx"
		pipx install "uv==${UV_VERSION}"
	fi
	# uv installs to ~/.local/bin by default; make it visible this session
	export PATH="${HOME}/.local/bin:${PATH}"
	check_uv_installed || error_exit "uv installation failed"
}

# Get Python installation choice interactively or use default
get_python_choice() {
	PYTHON_CHOICE="${_arg_python_choice}"

	# In non-interactive mode, use the provided argument
	if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
		log "Non-interactive mode, using Python installation method: ${PYTHON_CHOICE}"
	else
		log "How would you like to install Python packages?"
		# Interactive mode - show current choice and allow override
		while true; do
			echo "1) active-venv: Use the active virtual environment"
			echo "2) new-venv: [DEFAULT] Create a new Python virtual environment (venv) at ${_arg_new_venv_location}"
			echo "3) system-python: Use the system pathing, available for multiple users. *** NOT RECOMMENDED UNLESS YOU ARE SURE ***"
			echo "4) pipx: Use pipx for isolated package installation"
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
	fi

	# Validate --use-uv flag
	if [[ "${_arg_use_uv}" = "on" ]]; then
		if [[ "${PYTHON_CHOICE}" = "pipx" ]]; then
			warn "--use-uv is not compatible with pipx, ignoring --use-uv flag"
			_arg_use_uv="off"
		else
			if ! check_uv_installed; then
				install_uv
			fi
			log "Using uv instead of pip for package installation"
		fi
	fi

	if [[ -n "${_arg_python_version}" && "${_arg_use_uv}" != "on" ]]; then
		warn "--python-version is only honored with --use-uv; ignoring"
		_arg_python_version=""
	fi

	# Set up Python environment based on choice
	case ${PYTHON_CHOICE} in
		"active-venv")
			if [[ -z "${VIRTUAL_ENV:-}" ]]; then
				error "No active virtual environment detected!"
				error_exit "Please activate your virtual environment first and try again"
			fi
			log "Using active virtual environment: ${VIRTUAL_ENV}"
			INSTALLED_IN_VENV=0
			if [[ "${_arg_use_uv}" = "on" ]]; then
				PYTHON_INSTALL_CMD="uv pip install"
			else
				PYTHON_INSTALL_CMD="pip install"
			fi
			;;
		"system-python")
			log "Using system pathing"
			INSTALLED_IN_VENV=1
			# Check Python version to determine if --break-system-packages is needed (Python 3.11+)
			PYTHON_VERSION_MINOR=$(python3 -c "import sys; print(f'{sys.version_info.minor}')")
			if [[ "${_arg_use_uv}" = "on" ]]; then
				if [[ ${PYTHON_VERSION_MINOR} -gt 10 ]]; then
					PYTHON_INSTALL_CMD="uv pip install --system --break-system-packages"
				else
					PYTHON_INSTALL_CMD="uv pip install --system"
				fi
			else
				if [[ ${PYTHON_VERSION_MINOR} -gt 10 ]]; then
					PYTHON_INSTALL_CMD="pip install --break-system-packages"
				else
					PYTHON_INSTALL_CMD="pip install"
				fi
			fi
			;;
		"pipx")
			log "Using pipx for isolated package installation"
			# adding quotes around PIPX_ENSUREPATH_EXTRAS means they won't be
			# interpreted, which is exactly what we want them to be
			# shellcheck disable=2086
			pipx ensurepath ${PIPX_ENSUREPATH_EXTRAS}
			# Enable the pipx path in this shell session
			export PATH="${PATH}:${HOME}/.local/bin/"
			INSTALLED_IN_VENV=1
			PYTHON_INSTALL_CMD="pipx install ${PIPX_INSTALL_EXTRAS}"
			;;
		"new-venv"|*)
			log "Setting up new Python virtual environment"
			if [[ "${_arg_use_uv}" = "on" ]]; then
				# uv creates the venv (and provisions the interpreter when a
				# version is pinned), avoiding ensurepip and the system Python.
				# --seed installs pip into the venv: ttis_resolve_versions and
				# users' own workflows expect `pip` to exist there.
				if [[ -n "${_arg_python_version}" ]]; then
					uv venv --seed --allow-existing --python "${_arg_python_version}" "${_arg_new_venv_location}"
				else
					uv venv --seed --allow-existing "${_arg_new_venv_location}"
				fi
			else
				python3 -m venv "${_arg_new_venv_location}"
			fi
			# shellcheck disable=SC1091 # Must exist after previous command
			source "${_arg_new_venv_location}/bin/activate"
			INSTALLED_IN_VENV=0
			if [[ "${_arg_use_uv}" = "on" ]]; then
				PYTHON_INSTALL_CMD="uv pip install"
			else
				PYTHON_INSTALL_CMD="pip install"
			fi
			;;
	esac

	# PYTHON_ENV_LOCATION / PYTHON_ENV_PYTHON_VERSION are consumed by ttis_export,
	# which is inlined into install.sh at build time, so shellcheck -x on install.m4
	# can't see the use here.
	# shellcheck disable=SC2034
	case "${PYTHON_CHOICE}" in
		"new-venv"|"active-venv") PYTHON_ENV_METHOD="venv";   PYTHON_ENV_LOCATION="${VIRTUAL_ENV:-}" ;;
		"system-python")          PYTHON_ENV_METHOD="global"; PYTHON_ENV_LOCATION="" ;;
		"pipx")                   PYTHON_ENV_METHOD="pipx";   PYTHON_ENV_LOCATION="" ;;
	esac

	# Record the venv interpreter version (python3 is the venv after activation)
	# so it round-trips through ttis_export/import.
	# shellcheck disable=SC2034
	if [[ "${PYTHON_ENV_METHOD}" == "venv" ]]; then
		PYTHON_ENV_PYTHON_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "")"
	else
		PYTHON_ENV_PYTHON_VERSION=""
	fi

}

# Function to check if a container runtime is installed
check_container_runtime_installed() {
	command -v docker &> /dev/null || command -v podman &> /dev/null
}

# Function to setup rootless Podman
setup_rootless_podman() {
	log "Configuring rootless Podman"
	# Add GUIDs/UIDs for rootless Podman
	# See https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md
	sudo usermod --add-subgids 10000-75535 "$(whoami)"
	sudo usermod --add-subuids 10000-75535 "$(whoami)"
}

# Install Metalium container
install_metalium_container() {
	log "Installing Metalium via container"

	# Create wrapper script directory
	mkdir -p "${_arg_metalium_container_script_dir}" || error_exit "Failed to create script directory"

	# Create wrapper script
	log "Creating wrapper script..."
	cat > "${_arg_metalium_container_script_dir}/${_arg_metalium_container_script_name}" << EOF
#!/bin/bash
# Wrapper script for tt-metalium using OCI container runtime

# Image configuration
METALIUM_IMAGE="${_arg_metalium_image_url}:${_arg_metalium_image_tag}"

# Run the command using container runtime

${CONTAINER_CLI} run --rm -it \\
  --privileged \\
  --log-driver none \\
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
	chmod +x "${_arg_metalium_container_script_dir}/${_arg_metalium_container_script_name}" || error_exit "Failed to make script executable"

	# Check if the directory is in PATH
	if [[ ":${PATH}:" != *":${_arg_metalium_container_script_dir}:"* ]]; then
		warn "${_arg_metalium_container_script_dir} is not in your PATH."
		warn "A restart may fix this, or you may need to update your shell RC"
	fi

	# Pull the image
	if [[ "${_arg_pull_container_images}" == "on" ]]; then
		log "Pulling the tt-metalium image (this may take a while)..."
		# shellcheck disable=2086 # CONTAINER_PULL_PREFIX is empty or "sudo"; must word-split
		${CONTAINER_PULL_PREFIX} "${CONTAINER_CLI}" pull "${_arg_metalium_image_url}:${_arg_metalium_image_tag}" || error "Failed to pull image"
	else
		log "Skipping tt-metalium image pull (--no-pull-container-images); the ${_arg_metalium_container_script_name} wrapper will pull it on first run"
	fi

	log "Metalium installation completed"
	return 0
}

# Install Metalium "models" container
install_metalium_models_container() {
	log "Installing Metalium Models Container via OCI container runtime"
	local METALIUM_MODELS_SCRIPT_DIR="${HOME}/.local/bin"
	local METALIUM_MODELS_SCRIPT_NAME="tt-metalium-models"

	# Create wrapper script directory
	mkdir -p "${METALIUM_MODELS_SCRIPT_DIR}" || error_exit "Failed to create script directory"

	# Create wrapper script
	log "Creating wrapper script..."
	cat > "${METALIUM_MODELS_SCRIPT_DIR}/${METALIUM_MODELS_SCRIPT_NAME}" << EOF
#!/bin/bash
# Wrapper script for tt-metalium-models using OCI container runtime

echo "================================================================================"
echo "NOTE: This container tool for tt-metalium is meant to enable users to try out"
echo "      demos, and is not meant for production use. This container is liable to"
echo "      to change at anytime."
echo ""
echo "      For more information see https://github.com/tenstorrent/tt-metal/issues/25602"
echo "================================================================================"

# Image configuration
METALIUM_IMAGE="${METALIUM_MODELS_IMAGE_URL}:${METALIUM_MODELS_IMAGE_TAG}"

# Run the command using container runtime
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
${CONTAINER_CLI} run --rm -it \\
  --privileged \\
  --log-driver none \\
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
	chmod +x "${METALIUM_MODELS_SCRIPT_DIR}/${METALIUM_MODELS_SCRIPT_NAME}" || error_exit "Failed to make script executable"

	# Check if the directory is in PATH
	if [[ ":${PATH}:" != *":${METALIUM_MODELS_SCRIPT_DIR}:"* ]]; then
		warn "${METALIUM_MODELS_SCRIPT_DIR} is not in your PATH."
		warn "A restart may fix this, or you may need to update your shell RC"
	fi

	# Pull the image
	if [[ "${_arg_pull_container_images}" == "on" ]]; then
		log "Pulling the tt-metalium-models image (this may take a while)..."
		# shellcheck disable=2086 # CONTAINER_PULL_PREFIX is empty or "sudo"; must word-split
		${CONTAINER_PULL_PREFIX} "${CONTAINER_CLI}" pull "${METALIUM_MODELS_IMAGE_URL}:${METALIUM_MODELS_IMAGE_TAG}" || error "Failed to pull image"
	else
		log "Skipping tt-metalium-models image pull (--no-pull-container-images); the ${METALIUM_MODELS_SCRIPT_NAME} wrapper will pull it on first run"
	fi

	log "Metalium Models installation completed"
	return 0
}

get_metalium_container_choice() {
	# In non-interactive mode, use the provided arguments
	if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
		log "Non-interactive mode, using Metalium container installation preference: ${_arg_install_metalium_container}"
		log "Non-interactive mode, using Metalium Models installation preference: ${_arg_install_metalium_models_container}"
		return
	fi
	# Only ask if a container runtime is installed or will be installed
	if [[ "${_arg_install_container_runtime}" != "none" ]] || check_container_runtime_installed; then
		# Interactive mode - allow override
		log "Would you like to install the TT-Metalium slim container?"
		log "This container is appropriate if you only need to use TT-NN"
		if confirm "Install Metalium"; then
			_arg_install_metalium_container="on"
		else
			_arg_install_metalium_container="off"
		fi
	else
		# Container runtime won't be installed, so don't install Metalium
		_arg_install_metalium_container="off"
		warn "Container runtime is not and will not be installed, skipping Metalium container installation"
	fi
	# Only ask if a container runtime is installed or will be installed
	if [[ "${_arg_install_container_runtime}" != "none" ]] || check_container_runtime_installed; then
		# Interactive mode - allow override
		log "Would you like to install the TT-Metalium Model Demos container?"
		log "This container is best for users who need more TT-Metalium functionality, such as running prebuilt models, but it's large (8GB)"
		if confirm "Install Metalium Models"; then
			_arg_install_metalium_models_container="on"
		else
			_arg_install_metalium_models_container="off"
		fi
	else
		# Container runtime won't be installed, so don't install Metalium
		_arg_install_metalium_models_container="off"
		warn "Container runtime is not and will not be installed, skipping Metalium Models container installation"
	fi
}

# Install Forge container
install_forge_container() {
	log "Installing Forge via container"

	# Create wrapper script directory
	mkdir -p "${_arg_forge_container_script_dir}" || error_exit "Failed to create script directory"

	# Create wrapper script
	log "Creating wrapper script..."
	cat > "${_arg_forge_container_script_dir}/${_arg_forge_container_script_name}" << EOF
#!/bin/bash
# Wrapper script for tt-forge using OCI container runtime

# Image configuration
FORGE_IMAGE="${_arg_forge_image_url}:${_arg_forge_image_tag}"

# Run the command using container runtime

${CONTAINER_CLI} run --rm -it \\
  --privileged \\
  --log-driver none \\
  --volume=/dev/hugepages:/dev/hugepages \\
  --volume=/dev/hugepages-1G:/dev/hugepages-1G \\
  --volume=/lib/modules:/lib/modules \\
  --volume=\${HOME}:/home/user \\
  --device=/dev/tenstorrent:/dev/tenstorrent \\
  --workdir=/home/user \\
  --env=DISPLAY=\${DISPLAY} \\
  --env=HOME=/home/user \\
  --env=TERM=\${TERM:-xterm-256color} \\
  --network=host \\
  --security-opt label=disable \\
  --entrypoint /bin/bash \\
  \${FORGE_IMAGE} "\$@"
EOF

	# Make the script executable
	chmod +x "${_arg_forge_container_script_dir}/${_arg_forge_container_script_name}" || error_exit "Failed to make script executable"

	# Check if the directory is in PATH
	if [[ ":${PATH}:" != *":${_arg_forge_container_script_dir}:"* ]]; then
		warn "${_arg_forge_container_script_dir} is not in your PATH."
		warn "A restart may fix this, or you may need to update your shell RC"
	fi

	# Pull the image
	if [[ "${_arg_pull_container_images}" == "on" ]]; then
		log "Pulling the tt-forge image (this may take a while)..."
		# shellcheck disable=2086 # CONTAINER_PULL_PREFIX is empty or "sudo"; must word-split
		${CONTAINER_PULL_PREFIX} "${CONTAINER_CLI}" pull "${_arg_forge_image_url}:${_arg_forge_image_tag}" || error "Failed to pull image"
	else
		log "Skipping tt-forge image pull (--no-pull-container-images); the ${_arg_forge_container_script_name} wrapper will pull it on first run"
	fi

	log "Forge installation completed"
	return 0
}

get_forge_container_choice() {
	# In non-interactive mode, use the provided arguments
	if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
		log "Non-interactive mode, using Forge container installation preference: ${_arg_install_forge_container}"
		return
	fi
	# Only ask if a container runtime is installed or will be installed
	if [[ "${_arg_install_container_runtime}" != "none" ]] || check_container_runtime_installed; then
		# Interactive mode - allow override
		log "Would you like to install the TT-Forge slim container?"
		if confirm "Install Forge"; then
			_arg_install_forge_container="on"
		else
			_arg_install_forge_container="off"
		fi
	else
		# Container runtime won't be installed, so don't install Forge
		_arg_install_forge_container="off"
		warn "Container runtime is not and will not be installed, skipping Forge container installation"
	fi
}

get_inference_server_choice() {
	# In non-interactive mode, use the provided argument
	if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
		log "Non-interactive mode, using tt-inference-server installation preference: ${_arg_install_inference_server}"
		return
	fi

	# Interactive mode - allow override
	log "Would you like to install tt-inference-server?"
	log "This will clone the inference server repository to ~/.local/lib and create a wrapper script"
	if confirm "Install tt-inference-server"; then
		_arg_install_inference_server="on"
	else
		_arg_install_inference_server="off"
	fi
}

get_studio_choice() {
	# In non-interactive mode, use the provided argument
	if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
		log "Non-interactive mode, using tt-studio installation preference: ${_arg_install_studio}"
		return
	fi

	# Interactive mode - allow override
	log "Would you like to install tt-studio?"
	log "This will clone the tt-studio repository to ~/.local/lib and create a wrapper script"
	if confirm "Install tt-studio"; then
		_arg_install_studio="on"
	else
		_arg_install_studio="off"
	fi
}

# Generic function to fetch latest version from any GitHub repository
# Usage: fetch_latest_version <repo> <prefix_to_remove>
# Returns: version string with prefix removed, or exits with error code
fetch_latest_version() {
	local repo="$1"
	local prefix_to_remove="${2:-}"

	if ! command -v jq &> /dev/null; then
		echo "Error: JQ is not installed!" >&2
		return 1  # jq not installed
	fi

	local response
	local response_headers
	local response_body
	local latest_version

	# Curl options
	# We always suppress connect headers (fixes issues with systems using proxies)
	# -D - dumps the headers to stdout
	curl_opts=(--suppress-connect-headers -D -)

	# SC is worried this might not exist, but argbash guarantees it will
    # shellcheck disable=SC2154
	if [[ "${_arg_verbose}" = "on" ]]; then
		curl_opts+=(-v)
	else
		curl_opts+=(-s -S)
	fi

	if [[ -n "${_arg_github_token}" ]]; then
		curl_opts+=(-H "Authorization: token ${_arg_github_token}")
	fi

	response=$(curl "${curl_opts[@]}" \
		https://api.github.com/repos/"${repo}"/releases/latest)

	# Split at the first blank line
	response_headers=$(echo "${response}" | sed '/^\r*$/,$d')
	response_body=$(echo "${response}" | sed '1,/^\r*$/d')

	if [[ "${_arg_verbose}" = "on" ]]; then
		echo "=== GitHub API Response Headers ===" >&2
		echo "${response_headers}" >&2
		echo "=== GitHub API Response Body ===" >&2
		echo "${response_body}" >&2
		echo "===================================" >&2
	fi

	# Check for GitHub API rate limit
	if echo "${response_headers}" | grep -qi "x-ratelimit-remaining: 0"; then
		echo "Error: GitHub API Rate Limit exceeded" >&2
		return 2  # GitHub API rate limit exceeded
	fi

	# Check if response body is valid JSON
	if ! echo "${response_body}" | jq . >/dev/null 2>&1; then
		echo "Error: Got invalid JSON from GitHub API" >&2
		return 3  # Invalid JSON response
	fi

	latest_version=$(echo "${response_body}" | jq -r '.tag_name' 2>/dev/null)

	# Check if we got a valid tag_name
	if [[ -z "${latest_version}" || "${latest_version}" == "null" ]]; then
		echo "Error: No tag name found in API response" >&2
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

install_tt_repos () {
	log "Installing TT repositories to your distribution package manager"
	case "${DISTRO_ID}" in
		"ubuntu")
			# Add the apt listing
			# shellcheck disable=2002
			echo "deb [signed-by=/etc/apt/keyrings/tt-pkg-key.asc] https://ppa.tenstorrent.com/ubuntu/ $( cat /etc/os-release | grep "^VERSION_CODENAME=" | sed 's/^VERSION_CODENAME=//' ) main" | sudo tee /etc/apt/sources.list.d/tenstorrent.list > /dev/null

			# Setup the keyring
			sudo mkdir -p /etc/apt/keyrings; sudo chmod 755 /etc/apt/keyrings

			# Download the key. Use curl, not wget: when wget's stdin is a tty and
			# the terminal's foreground process group shifts mid-download, it
			# assumes it was backgrounded and dumps its output to ./wget-log.
			sudo curl -fsSL -o /etc/apt/keyrings/tt-pkg-key.asc https://ppa.tenstorrent.com/tt-pkg-key.asc

			apt_get update
			;;
		"debian")
			# Add the apt listing
			# shellcheck disable=2002
			echo "deb [signed-by=/etc/apt/keyrings/tt-pkg-key.asc] https://ppa.tenstorrent.com/debian/ $( cat /etc/os-release | grep "^VERSION_CODENAME=" | sed 's/^VERSION_CODENAME=//' ) main" | sudo tee /etc/apt/sources.list.d/tenstorrent.list > /dev/null

			# Setup the keyring
			sudo mkdir -p /etc/apt/keyrings; sudo chmod 755 /etc/apt/keyrings

			# Download the key. Use curl, not wget: when wget's stdin is a tty and
			# the terminal's foreground process group shifts mid-download, it
			# assumes it was backgrounded and dumps its output to ./wget-log.
			sudo curl -fsSL -o /etc/apt/keyrings/tt-pkg-key.asc https://ppa.tenstorrent.com/tt-pkg-key.asc

			apt_get update
			;;
		"fedora")
			sudo bash -c 'cat > /etc/yum.repos.d/tenstorrent.repo << EOF
[Tenstorrent]
name=Tenstorrent
baseurl=https://ppa.tenstorrent.com/fedora
enabled=1
gpgcheck=1
gpgkey=http://ppa.tenstorrent.com/tt-pkg-key.asc
EOF'
			;;
		"rhel"|"centos")
			warn "RHEL and CentOS are not officially supported. Using Fedora repos."
			sudo bash -c 'cat > /etc/yum.repos.d/tenstorrent.repo << EOF
[Tenstorrent]
name=Tenstorrent
baseurl=https://ppa.tenstorrent.com/fedora
enabled=1
gpgcheck=1
gpgkey=http://ppa.tenstorrent.com/tt-pkg-key.asc
EOF'
			;;
		*)
			error_exit "Unsupported distro: ${DISTRO_ID}"
			;;
	esac
}

install_inference_server () {
	log "Installing tt-inference-server"
	local INFERENCE_SERVER_LIB_DIR="${HOME}/.local/lib"
	local INFERENCE_SERVER_BIN_DIR="${HOME}/.local/bin"
	local INFERENCE_SERVER_SCRIPT_NAME="tt-inference-server"
	local INFERENCE_SERVER_REPO_URL="https://github.com/tenstorrent/tt-inference-server.git"

	# Create directories
	mkdir -p "${INFERENCE_SERVER_LIB_DIR}" || error_exit "Failed to create library directory"
	mkdir -p "${INFERENCE_SERVER_BIN_DIR}" || error_exit "Failed to create bin directory"

	# Clone the repository
	log "Cloning tt-inference-server repository..."
	if [[ -d "${INFERENCE_SERVER_LIB_DIR}/tt-inference-server" ]]; then
		warn "tt-inference-server directory already exists at ${INFERENCE_SERVER_LIB_DIR}/tt-inference-server"
		warn "Skipping clone, will create wrapper script only"
	else
		git clone "${INFERENCE_SERVER_REPO_URL}" "${INFERENCE_SERVER_LIB_DIR}/tt-inference-server" || error_exit "Failed to clone tt-inference-server"
	fi

	# Create wrapper script
	log "Creating wrapper script..."
	cat > "${INFERENCE_SERVER_BIN_DIR}/${INFERENCE_SERVER_SCRIPT_NAME}" << 'EOF'
#!/bin/bash

cd ${HOME}/.local/lib/tt-inference-server
python ${HOME}/.local/lib/tt-inference-server/run.py "$@"
EOF

	# Make the script executable
	chmod +x "${INFERENCE_SERVER_BIN_DIR}/${INFERENCE_SERVER_SCRIPT_NAME}" || error_exit "Failed to make script executable"

	# Check if the directory is in PATH
	if [[ ":${PATH}:" != *":${INFERENCE_SERVER_BIN_DIR}:"* ]]; then
		warn "${INFERENCE_SERVER_BIN_DIR} is not in your PATH."
		warn "A restart may fix this, or you may need to update your shell RC"
	fi

	log "tt-inference-server installation completed"
	return 0
}

install_studio () {
	log "Installing tt-studio"
	local STUDIO_LIB_DIR="${HOME}/.local/lib"
	local STUDIO_BIN_DIR="${HOME}/.local/bin"
	local STUDIO_SCRIPT_NAME="tt-studio"
	local STUDIO_REPO_URL="https://github.com/tenstorrent/tt-studio.git"

	# Create directories
	mkdir -p "${STUDIO_LIB_DIR}" || error_exit "Failed to create library directory"
	mkdir -p "${STUDIO_BIN_DIR}" || error_exit "Failed to create bin directory"

	# Clone the repository
	log "Cloning tt-studio repository..."
	if [[ -d "${STUDIO_LIB_DIR}/tt-studio" ]]; then
		warn "tt-studio directory already exists at ${STUDIO_LIB_DIR}/tt-studio"
		warn "Skipping clone, will create wrapper script only"
	else
		git clone "${STUDIO_REPO_URL}" "${STUDIO_LIB_DIR}/tt-studio" || error_exit "Failed to clone tt-studio"
	fi

	# Create wrapper script
	log "Creating wrapper script..."
	cat > "${STUDIO_BIN_DIR}/${STUDIO_SCRIPT_NAME}" << 'EOF'
#!/bin/bash

cd "${HOME}/.local/lib/tt-studio"
python "${HOME}/.local/lib/tt-studio/run.py" "$@"
EOF

	# Make the script executable
	chmod +x "${STUDIO_BIN_DIR}/${STUDIO_SCRIPT_NAME}" || error_exit "Failed to make script executable"

	# Check if the directory is in PATH
	if [[ ":${PATH}:" != *":${STUDIO_BIN_DIR}:"* ]]; then
		warn "${STUDIO_BIN_DIR} is not in your PATH."
		warn "A restart may fix this, or you may need to update your shell RC"
	fi

	log "tt-studio installation completed"
	return 0
}

# Install Podman and podman-docker shim
install_podman() {
	log "Installing Podman and podman-docker shim"
	case "${PKG_MANAGER}" in
		"apt-get")
			apt_get install -y podman podman-docker
			;;
		"dnf")
			sudo dnf install -y podman podman-docker podman-compose
			;;
		*)
			error_exit "Unsupported package manager: ${PKG_MANAGER}"
			;;
	esac
}

# Install Docker using the official Docker installation script
install_docker() {
	log "Installing Docker"
	cd "${WORKDIR}"

	# Download Docker installation script
	curl -fsSL https://get.docker.com -o get-docker.sh
	verify_download "get-docker.sh"

	# Run the Docker installation script
	sudo sh get-docker.sh

	# Add current user to docker group
	sudo usermod -aG docker "$(whoami)"

	sudo systemctl start docker

	log "Docker installation completed. You may need to log out and back in for group membership to take effect."
}

# Main installation script
main() {
	echo -e "${LOGO}"
	echo # newline
	INSTALLER_VERSION="__INSTALLER_DEVELOPMENT_BUILD__" # Set to semver at release time by GitHub Actions
	log "Welcome to tenstorrent!"
	log "This is tt-installer version ${INSTALLER_VERSION}"
	log "Log is at ${LOG_FILE}"

	log "This script will install drivers and tooling and properly configure your tenstorrent hardware."

	if [[ -n "${_arg_export_schema:-}" ]]; then
		warn "--export-schema is a developer/CI feature for capturing installer state; it is not needed for a normal install."
	fi

	normalize_options || return 1

	# Resolve state file paths to absolute now, before any cd changes the working directory.
	if [[ -n "${_arg_export_schema:-}" && "${_arg_export_schema}" != /* ]]; then
		_arg_export_schema="$(pwd)/${_arg_export_schema}"
	fi
	# --versions may be a literal channel ('release'/'rolling') or a path to a .ttis file.
	if [[ "${_arg_versions}" != "release" && "${_arg_versions}" != "rolling" && "${_arg_versions}" != /* ]]; then
		_arg_versions="$(pwd)/${_arg_versions}"
	fi

	# Detect distro early so PKG_MANAGER is set before ttis_import needs it.
	detect_distro
	resolve_base_packages

	# tenstorrent-dkms < 2.9.0 does not build on RHEL 9.4+ kernels: those
	# kernels backport the one-argument class_create() and the removal of
	# pci_enable/disable_pcie_error_reporting() while LINUX_VERSION_CODE still
	# reports 5.14, so tt-kmd's version guards select the pre-6.x API path and
	# the DKMS build fails (issue #93). tt-kmd 2.9.0 added TT_RHEL_RELEASE_GE
	# guards for this; refuse older pins on RHEL/CentOS up front instead of
	# letting dkms fail deep inside the install.
	if [[ "${_arg_install_kmd}" != "off" && -n "${_arg_kmd_version}" ]] \
		&& { [[ "${DISTRO_ID}" = "rhel" ]] || [[ "${DISTRO_ID}" = "centos" ]]; } \
		&& [[ "${_arg_kmd_version}" != "2.9.0" \
			&& "$(printf '%s\n2.9.0\n' "${_arg_kmd_version}" | sort -V | head -n 1)" = "${_arg_kmd_version}" ]]; then
		error_exit "--kmd-version ${_arg_kmd_version} cannot be installed on ${DISTRO_ID}: tenstorrent-dkms < 2.9.0 does not build on RHEL 9.4+ kernels (issue #93). Use --kmd-version 2.9.0 or newer."
	fi

	# Version arguments given on the command line take precedence over versions
	# pinned by the 'release' channel or imported from a .ttis file: capture
	# them before the import and re-apply them afterwards.
	declare -A user_versions=()
	for _ver_var in _arg_kmd_version _arg_fw_version _arg_systools_version \
			_arg_smi_version _arg_flash_version _arg_topology_version _arg_sfpi_version; do
		if [[ -n "${!_ver_var}" ]]; then
			user_versions["${_ver_var}"]="${!_ver_var}"
		fi
	done

	# Select the version channel. The default ('release') is applied silently;
	# explicit non-default selections are logged.
	case "${_arg_versions}" in
		rolling)
			log "Version channel: rolling — installing the latest available version of each component"
			;;
		release)
			if fetch_golden_schema; then
				ttis_import_versions "${GOLDEN_SCHEMA_FILE}"
			else
				warn "Falling back to rolling versions (latest of everything)"
			fi
			;;
		*)
			# A path to a .ttis file: full non-interactive import (used by CI/automation).
			log "Version channel: importing state from ${_arg_versions}"
			# shellcheck disable=SC2034
			TTIS_VERBOSE=1
			ttis_import "${_arg_versions}"
			;;
	esac

	if [[ ${#user_versions[@]} -gt 0 ]]; then
		for _ver_var in "${!user_versions[@]}"; do
			printf -v "${_ver_var}" '%s' "${user_versions[${_ver_var}]}"
		done
		log "Component versions given on the command line take precedence over channel pins"
	fi
	unset _ver_var user_versions

	# Post-import defaults so dry-run and a real install resolve the same plan.
	# A .ttis import can overwrite earlier normalization, and non-interactive
	# mode must map reboot=ask to never before either path continues.
	if [[ "${_arg_dry_run}" = "on" ]]; then
		_arg_mode_non_interactive="on"
	fi
	if [[ "${_arg_mode_non_interactive}" = "on" ]]; then
		set_non_interactive_defaults
	fi
	normalize_options || return 1
	disable_unused_container_runtime

	# Dry-run deliberately stops before prompts, sudo, package managers, Python
	# environment creation, payload downloads, clones, wrapper creation, export,
	# or reboot. Read-only release metadata may be fetched to resolve the plan.
	if [[ "${_arg_dry_run}" = "on" ]]; then
		resolve_container_runtime
		resolve_firmware_action
		if [[ "${RESOLVED_FIRMWARE_ACTION}" != "skip" && -z "${_arg_fw_version:-}" ]]; then
			_arg_fw_version=$(fetch_latest_version "tenstorrent/tt-system-firmware" "v") || return 1
		fi
		build_package_registry
		resolve_package_actions
		render_install_plan
		if [[ "${INSTALLER_SOURCE_ONLY}" != "1" ]]; then
			rm -rf -- "${WORKDIR}"
		fi
		return 0
	fi

	# Remember whether non-interactive mode was requested explicitly, before
	# maybe_enable_default_mode can turn it on as part of the default path.
	user_non_interactive="${_arg_mode_non_interactive}"
	maybe_enable_default_mode
	log "Starting installation"

	# Log special mode settings. Values that merely match the installer's
	# defaults are not announced; explicit user selections are.
	if [[ "${user_non_interactive}" = "on" ]]; then
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
	if [[ "${_arg_install_container_runtime}" = "none" ]]; then
		warn "Container runtime installation will be skipped"
	fi
	if [[ "${_arg_install_metalium_container}" = "off" ]]; then
		warn "Metalium container installation will be skipped"
	fi
	if [[ "${_arg_install_forge_container}" = "off" ]] && arg_was_passed "--no-install-forge-container"; then
		warn "Forge container installation will be skipped"
	fi
	if [[ "${_arg_install_sfpi}" = "off" ]]; then
		warn "SFPI installation will be skipped"
	fi
	if [[ "${_arg_install_inference_server}" = "off" ]]; then
		warn "tt-inference-server installation will be skipped"
	fi
	if [[ "${_arg_install_studio}" = "off" ]]; then
		warn "tt-studio installation will be skipped"
	fi
	# shellcheck disable=SC2154
	if [[ "${_arg_install_tt_flash}" = "off" ]]; then
		warn "TT-Flash installation will be skipped"
	fi
	if [[ "${_arg_update_firmware}" = "off" ]]; then
		warn "Firmware update will be skipped"
	fi
	if [[ "${_arg_update_firmware}" = "force" ]] && arg_was_passed "--update-firmware"; then
		warn "Firmware will be forcibly updated"
	fi
	if [[ "${_arg_install_metalium_models_container}" = "on" ]]; then
		log "Metalium Models container will be installed"
	fi
	if [[ "${_arg_use_uv}" = "on" ]] && arg_was_passed "--use-uv"; then
		log "uv will be used instead of pip for package installation"
	fi

	log "Checking for sudo permissions... (may request password)"
	check_has_sudo_perms

	# Install base packages (distro already detected above)

	log "Installing base packages"
	case "${DISTRO_ID}" in
		ubuntu|debian)
			apt_get update
			apt_get install -y "${BASE_SYSTEM_PACKAGES[@]}"
			;;
		fedora)
			sudo dnf install -y "${BASE_SYSTEM_PACKAGES[@]}"
			;;
		rhel|centos)
			sudo dnf install -y "${BASE_BOOTSTRAP_PACKAGES[@]}"
			sudo dnf install -y "${BASE_SYSTEM_PACKAGES[@]}"
			;;
		*) error "Unsupported distribution: ${DISTRO_ID}"; return 1 ;;
	esac

	if [[ "${DISTRO_ID}" = "debian" ]] && ! version_at_least "${VERSION_ID:-0}" 13; then
		warn "rustc and cargo cannot be automatically installed on Debian. Ensure the latest versions are installed before continuing."
		warn "If you are unsure how to do this, use rustup: https://rustup.rs/"
	fi

	# Get Metalium container installation choice
	get_metalium_container_choice

	# Get Forge container installation choice
	get_forge_container_choice

	disable_unused_container_runtime

	# Get tt-inference-server installation choice
	get_inference_server_choice
	get_studio_choice

	# Python package installation preference
	get_python_choice
	install_tt_repos

	# Install container runtime if requested.
	# CONTAINER_PULL_PREFIX prefixes image pulls done during this run. Docker is
	# rootful and, when freshly installed, the user's new "docker" group membership
	# is not active in the current session, so same-session pulls must use sudo.
	# Podman is rootless, so sudo would push images into root's storage where the
	# user's wrapper scripts could not see them; leave the prefix empty there.
	requested_container_runtime="${_arg_install_container_runtime}"
	resolve_container_runtime
	_arg_install_container_runtime="${RESOLVED_CONTAINER_RUNTIME}"
	if [[ "${requested_container_runtime}" = "auto" && "${CONTAINER_RUNTIME_PRESENT}" = "1" ]]; then
		warn "A container runtime is already installed; skipping container runtime installation to avoid reinstalling it or creating package conflicts."
	else
		case "${RESOLVED_CONTAINER_RUNTIME}" in
			podman) install_podman; setup_rootless_podman ;;
			docker) log "No container runtime found, installing Docker"; install_docker; CONTAINER_PULL_PREFIX="sudo" ;;
			none) log "Skipping container runtime installation" ;;
		esac
	fi

	# 1. Build package_registry from TTIS_PACKAGE_MAP (defined in ttis.sh).
	# Format: "package_name|install_flag|version|type"
	# To add a package, edit TTIS_PACKAGE_MAP in ttis.sh — no changes needed here.
	# Build package_registry from TTIS_PACKAGE_MAP + current _arg_* variables.
	# Any extra packages imported from a .ttis file are appended from TTIS_IMPORTED_PACKAGES.
	build_package_registry
	resolve_package_actions
	local -a system_packages=("${SYSTEM_PACKAGES[@]+${SYSTEM_PACKAGES[@]}}")
	local -a system_downgrade_packages=()
	local -a python_packages=("${PYTHON_PACKAGES[@]+${PYTHON_PACKAGES[@]}}")

	# dnf cannot downgrade through install. Keep this environment-dependent
	# check outside resolve_package_actions so that the planner remains pure.
	if [[ "${PKG_MANAGER}" = "dnf" ]]; then
		for key in "${!package_registry[@]}"; do
			IFS='|' read -r pkg_name install_flag version pkg_type <<< "${package_registry[${key}]}"
			[[ "${install_flag}" = "on" && "${pkg_type}" = "system" && -n "${version}" ]] || continue
			installed_version=""
			if rpm -q "${pkg_name}" &>/dev/null; then
				installed_version="$(rpm -q --qf '%{VERSION}-%{RELEASE}' "${pkg_name}")"
			fi
			if [[ -n "${installed_version}" && "${version}" != "${installed_version}" && "$(printf '%s\n%s\n' "${version}" "${installed_version}" | sort -V | head -n 1)" = "${version}" ]]; then
				for i in "${!system_packages[@]}"; do
					[[ "${system_packages[${i}]}" = "${pkg_name}-${version}" ]] && unset 'system_packages[i]'
				 done
				system_downgrade_packages+=("${pkg_name}-${version}")
			fi
		done
		system_packages=("${system_packages[@]}")
	fi

	# 3. Act on the lists
	# Install system packages
	if [[ ${#system_packages[@]} -gt 0 ]]; then
		echo "Installing system packages: ${system_packages[*]}"
		if [[ "${PKG_MANAGER}" = "apt-get" ]]; then
			apt_get install -y "${system_packages[@]}"
		elif [[ "${PKG_MANAGER}" = "dnf" ]]; then
			sudo dnf install -y "${system_packages[@]}"
		fi
	fi

	# Downgrade system packages pinned below the installed version. Only used
	# with dnf; apt handles downgrades in the install above via --allow-downgrades.
	if [[ ${#system_downgrade_packages[@]} -gt 0 ]]; then
		echo "Downgrading system packages: ${system_downgrade_packages[*]}"
		sudo dnf downgrade -y "${system_downgrade_packages[@]}"
	fi

	# Install Python packages
	if [[ ${#python_packages[@]} -gt 0 ]]; then
		echo "Installing Python packages: ${python_packages[*]}"
		if [[ -z "${PYTHON_INSTALL_CMD:-}" ]]; then
			error_exit "PYTHON_INSTALL_CMD is not set. Python package installation cannot proceed."
		fi
		${PYTHON_INSTALL_CMD} "${python_packages[@]}"
	fi

	# Update firmware using tt-flash
	if [[ "${_arg_update_firmware}" = "off" ]]; then
		log "Skipping firmware update"
	else
		log "Updating firmware"

		# Check if tt-flash is installed and available
		if ! command -v tt-flash &> /dev/null; then
			error_exit "tt-flash is not installed or not in PATH. Please install tt-flash before attempting firmware update."
		fi

		FW_REPO="tenstorrent/tt-system-firmware"
		BACKUP_FW_REPO="tenstorrent/tt-firmware"
		FW_RELEASE_URL="https://github.com/${FW_REPO}/releases/download"
		BACKUP_FW_RELEASE_URL="https://github.com/${BACKUP_FW_REPO}/releases/download"

		if [[ -n "${_arg_fw_version:-}" ]]; then
			FW_VERSION=${_arg_fw_version}
		else
			FW_VERSION=$(fetch_latest_version "${FW_REPO}" "v");
		fi

		cd "${WORKDIR}"

		# Create FW_FILE based on FW_VERSION
		FW_FILE="fw_pack-${FW_VERSION}.fwbundle"

		# Download from GitHub releases
		if ! curl -fsSLO "${FW_RELEASE_URL}/v${FW_VERSION}/${FW_FILE}"; then
			warn "Tried URL ${FW_RELEASE_URL}/v${FW_VERSION}/${FW_FILE}"
			warn "Could not find firmware bundle at main URL- trying backup URL"
			if ! curl -fsSLO "${BACKUP_FW_RELEASE_URL}/v${FW_VERSION}/${FW_FILE}"; then
				error_exit "Could not download firmware bundle. Ensure firmware version is valid."
			fi
		fi

		verify_download "${FW_FILE}"

		if [[ "${_arg_update_firmware}" = "force" ]]; then
			tt-flash flash "${FW_FILE}" --force
		else
			tt-flash flash "${FW_FILE}"
		fi
	fi

	if [[ "${_arg_install_inference_server}" = "on" ]]; then
		install_inference_server
	fi

	if [[ "${_arg_install_studio}" = "on" ]]; then
		install_studio
	fi

	# Install Metalium container if requested
	if [[ "${_arg_install_metalium_container}" = "off" ]]; then
		warn "Skipping Metalium container installation"
	else
		if [[ "${_arg_install_container_runtime}" = "none" ]] && ! check_container_runtime_installed; then
			warn "No container runtime is installed. Cannot install Metalium container."
		else
			install_metalium_container
		fi
	fi

	# Install Metalium Models container if requested
	if [[ "${_arg_install_metalium_models_container}" = "on" ]]; then
		if [[ "${_arg_install_container_runtime}" = "none" ]] && ! check_container_runtime_installed; then
			warn "No container runtime is installed. Cannot install Metalium Models."
		else
			install_metalium_models_container
		fi
	fi

	if [[ "${INSTALLED_IN_VENV}" = "0" ]]; then
		warn "You'll need to run \"source ${VIRTUAL_ENV}/bin/activate\" to use tenstorrent's Python tools."
	fi

	# Install Forge container if requested
	if [[ "${_arg_install_forge_container}" = "off" ]]; then
		warn "Skipping Forge container installation"
	else
		if [[ "${_arg_install_container_runtime}" = "none" ]] && ! check_container_runtime_installed; then
			warn "No container runtime is installed. Cannot install Forge container."
		else
			install_forge_container
		fi
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
	if [[ "${_arg_install_forge_container}" = "on" ]]; then
		log "Use 'tt-forge' to access the Forge programming environment"
		log "Usage examples:"
		log "  tt-forge                   # Start an interactive shell"
		log "  tt-forge [command]         # Run a specific command"
		log "  tt-forge python script.py  # Run a Python script"
	fi
	if [[ "${_arg_install_inference_server}" = "on" ]]; then
		log "Use 'tt-inference-server' to run the inference server"
		log "The inference server has been installed to ~/.local/lib/tt-inference-server"
		log "Usage: tt-inference-server [arguments]"
	fi
	if [[ "${_arg_install_studio}" = "on" ]]; then
		log "Use 'tt-studio' to launch tt-studio"
		log "tt-studio has been installed to ~/.local/lib/tt-studio"
		log "Usage: tt-studio [arguments]"
	fi

	# Export state file if requested (an explicit selection, so ttis output is shown)
	if [[ -n "${_arg_export_schema:-}" ]]; then
		# shellcheck disable=SC2034
		TTIS_VERBOSE=1
		ttis_resolve_versions
		ttis_export "${_arg_export_schema}"
	fi

	# Log successful completion message
	log "✅ Installation completed successfully."
	log "Installation log saved to: ${LOG_FILE}"

	# Auto-reboot if specified
	if [[ "${_arg_reboot_option}" = "always" ]]; then
		log "Auto-reboot enabled. Rebooting now..."
		sudo reboot
	# Otherwise, ask if specified
	elif [[ "${_arg_reboot_option}" = "ask" ]]; then
		if confirm "Would you like to reboot now?"; then
			log "Rebooting..."
			sudo reboot
		fi
	fi
}

# Export only deterministic planning functions for source-based unit tests.
if [[ "${INSTALLER_SOURCE_ONLY}" = "1" ]]; then
	export -f normalize_options resolve_base_packages build_package_registry \
		resolve_package_actions disable_unused_container_runtime \
		resolve_container_runtime resolve_firmware_action \
		render_install_plan
fi

# Start installation unless the generated script is being sourced by a test.
ORIGINAL_ARGS=("$@")
if [[ "${INSTALLER_SOURCE_ONLY}" != "1" ]]; then
	main "$@"
fi

# ] <-- needed because of Argbash

# vim: noai:ts=4:sw=4:ft=bash
