#!/bin/bash

# SPDX-FileCopyrightText: © 2025 Tenstorrent AI ULC
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Logo
LOGO=$(cat << "EOF"
   __                  __                             __
  / /____  ____  _____/ /_____  _____________  ____  / /_
 / __/ _ \/ __ \/ ___/ __/ __ \/ ___/ ___/ _ \/ __ \/ __/
/ /_/  __/ / / (__  ) /_/ /_/ / /  / /  /  __/ / / / /_
\__/\___/_/ /_/____/\__/\____/_/  /_/   \___/_/ /_/\__/

                    UNINSTALLER
EOF
)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=0
FORCE=0
KEEP_VENV=0
KEEP_SYSTEM_PACKAGES=0

# Paths
VENV_PATH="${HOME}/.tenstorrent-venv"
LOCAL_LIB_DIR="${HOME}/.local/lib"
LOCAL_BIN_DIR="${HOME}/.local/bin"

# log messages
log() {
    local msg="[INFO] $1"
    echo -e "${GREEN}${msg}${NC}"
}

error() {
    local msg="[ERROR] $1"
    echo -e "${RED}${msg}${NC}"
}

warn() {
    local msg="[WARNING] $1"
    echo -e "${YELLOW}${msg}${NC}"
}

# Function to prompt for yes/no
confirm() {
    if [[ "${FORCE}" -eq 1 ]]; then
        return 0
    fi

    while true; do
        read -rp "$1 [y/N] " yn
        case ${yn} in
            [Yy]* ) return 0;;
            [Nn]* | "" ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Execute or print command based on dry-run mode
run_cmd() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# Execute sudo command or print based on dry-run mode
run_sudo() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "[DRY-RUN] sudo $*"
    else
        sudo "$@"
    fi
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID=${ID}
        case ${DISTRO_ID} in
            ubuntu|debian|fedora|rhel|centos)
                ;;
            *)
                if [[ -n "${ID_LIKE:-}" ]]; then
                    for id_like_distro in ${ID_LIKE}; do
                        case ${id_like_distro} in
                            ubuntu|debian|fedora|rhel)
                                DISTRO_ID=${id_like_distro}
                                break
                                ;;
                        esac
                    done
                fi
                ;;
        esac
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

# Remove tt-activate alias from shell RC files
remove_venv_alias() {
    log "Removing tt-activate alias from shell RC files..."

    local rc_files=(
        "${HOME}/.bashrc"
        "${HOME}/.zshrc"
        "${HOME}/.bash_profile"
        "${HOME}/.profile"
    )

    for rc_file in "${rc_files[@]}"; do
        if [[ -f "${rc_file}" ]]; then
            # Check if alias exists
            if grep -q "alias tt-activate=" "${rc_file}" 2>/dev/null; then
                log "Found tt-activate alias in ${rc_file}"

                if [[ "${DRY_RUN}" -eq 1 ]]; then
                    echo "[DRY-RUN] Would remove tt-activate alias from ${rc_file}"
                else
                    # Create backup
                    cp "${rc_file}" "${rc_file}.tt-backup"

                    # Remove the alias line and the comment above it
                    # Using a temporary file for portability
                    local tmp_file
                    tmp_file=$(mktemp)

                    # Remove lines containing tt-activate alias and the comment
                    grep -v "alias tt-activate=" "${rc_file}" | \
                        grep -v "# Tenstorrent virtual environment alias" > "${tmp_file}"

                    # Remove any resulting double blank lines
                    cat -s "${tmp_file}" > "${rc_file}"
                    rm -f "${tmp_file}"

                    log "Removed tt-activate alias from ${rc_file} (backup: ${rc_file}.tt-backup)"
                fi
            fi
        fi
    done
}

# Remove Python virtual environment
remove_venv() {
    if [[ "${KEEP_VENV}" -eq 1 ]]; then
        warn "Keeping Python virtual environment as requested"
        return
    fi

    if [[ -d "${VENV_PATH}" ]]; then
        log "Removing Python virtual environment at ${VENV_PATH}"
        if confirm "Remove ${VENV_PATH}?"; then
            run_cmd rm -rf "${VENV_PATH}"
            log "Removed ${VENV_PATH}"
        else
            warn "Skipped removing ${VENV_PATH}"
        fi
    else
        log "Python virtual environment not found at ${VENV_PATH}"
    fi
}

# Remove installed repositories
remove_repositories() {
    local repos=(
        "tt-inference-server"
        "tt-studio"
    )

    for repo in "${repos[@]}"; do
        local repo_path="${LOCAL_LIB_DIR}/${repo}"
        if [[ -d "${repo_path}" ]]; then
            log "Found ${repo} at ${repo_path}"
            if confirm "Remove ${repo_path}?"; then
                run_cmd rm -rf "${repo_path}"
                log "Removed ${repo_path}"
            else
                warn "Skipped removing ${repo_path}"
            fi
        fi
    done
}

# Remove wrapper scripts
remove_wrapper_scripts() {
    local scripts=(
        "tt-metalium"
        "tt-metalium-models"
        "tt-inference-server"
        "tt-studio"
    )

    log "Removing wrapper scripts..."

    for script in "${scripts[@]}"; do
        local script_path="${LOCAL_BIN_DIR}/${script}"
        if [[ -f "${script_path}" ]]; then
            log "Removing ${script_path}"
            run_cmd rm -f "${script_path}"
        fi
    done
}

# Remove Podman images
remove_podman_images() {
    if ! command -v podman &> /dev/null; then
        log "Podman not installed, skipping image removal"
        return
    fi

    # Search patterns for Tenstorrent images
    local image_patterns=(
        "ghcr.io/tenstorrent/tt-metal/tt-metalium"
    )

    log "Checking for Tenstorrent Podman images..."

    # Get all images with full repository:tag format
    local all_images
    all_images=$(podman images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)

    if [[ -z "${all_images}" ]]; then
        log "No Podman images found"
        return
    fi

    for pattern in "${image_patterns[@]}"; do
        # Find matching images with their tags
        local matching_images
        matching_images=$(echo "${all_images}" | grep "${pattern}" || true)

        if [[ -n "${matching_images}" ]]; then
            while IFS= read -r full_image; do
                [[ -z "${full_image}" ]] && continue
                log "Found Podman image: ${full_image}"
                if confirm "Remove Podman image ${full_image}?"; then
                    run_cmd podman rmi -f "${full_image}" || warn "Failed to remove ${full_image}"
                else
                    warn "Skipped removing ${full_image}"
                fi
            done <<< "${matching_images}"
        fi
    done
}

# Remove Python packages (pipx or pip)
remove_python_packages() {
    local packages=(
        "tt-flash"
        "tt-smi"
        "tt-topology"
    )

    log "Removing Python packages..."

    # Try pipx first
    if command -v pipx &> /dev/null; then
        for pkg in "${packages[@]}"; do
            if pipx list 2>/dev/null | grep -q "${pkg}"; then
                log "Removing ${pkg} via pipx"
                run_cmd pipx uninstall "${pkg}" || warn "Failed to uninstall ${pkg} via pipx"
            fi
        done
    fi

    # Try pip in venv or system
    if [[ -f "${VENV_PATH}/bin/pip" ]]; then
        log "Removing packages from venv..."
        for pkg in "${packages[@]}"; do
            if "${VENV_PATH}/bin/pip" show "${pkg}" &>/dev/null; then
                run_cmd "${VENV_PATH}/bin/pip" uninstall -y "${pkg}" || warn "Failed to uninstall ${pkg}"
            fi
        done
    fi
}

# Remove DKMS module manually if needed
remove_dkms_module() {
    local module_name="tenstorrent"

    # Check if dkms command exists
    if ! command -v dkms &> /dev/null; then
        return 0
    fi

    # Get list of installed tenstorrent DKMS modules
    local dkms_status
    dkms_status=$(dkms status 2>/dev/null | grep "^${module_name}" || true)

    if [[ -n "${dkms_status}" ]]; then
        log "Found DKMS modules: ${dkms_status}"
        # Extract version from dkms status (format: "tenstorrent/2.6.0-rc1, ...")
        while IFS= read -r line; do
            local version
            version=$(echo "${line}" | sed -n 's/^tenstorrent[,/]\s*\([^,]*\).*/\1/p')
            if [[ -n "${version}" ]]; then
                log "Removing DKMS module tenstorrent/${version}..."
                run_sudo dkms remove "tenstorrent/${version}" --all 2>/dev/null || true
            fi
        done <<< "${dkms_status}"
    fi
}

# Remove system packages
remove_system_packages() {
    if [[ "${KEEP_SYSTEM_PACKAGES}" -eq 1 ]]; then
        warn "Keeping system packages as requested"
        return
    fi

    local packages=(
        "tenstorrent-dkms"
        "tenstorrent-tools"
        "sfpi"
    )

    # Optional: also remove Podman-related packages
    local podman_packages=(
        "podman"
        "podman-docker"
        "podman-compose"
    )

    log "Checking for Tenstorrent system packages..."

    if confirm "Remove Tenstorrent system packages (tenstorrent-dkms, tenstorrent-tools, sfpi)?"; then
        # Clean up DKMS state before removing tenstorrent-dkms package
        remove_dkms_module

        if [[ "${PKG_MANAGER}" = "apt-get" ]]; then
            for pkg in "${packages[@]}"; do
                # Check for installed (ii) or config-files remaining (rc)
                if dpkg -l "${pkg}" 2>/dev/null | grep -q "^ii"; then
                    log "Removing ${pkg}..."
                    # Try normal purge first (removes config files too)
                    if ! run_sudo apt-get purge -y "${pkg}" 2>/dev/null; then
                        warn "Normal removal failed for ${pkg}"
                        warn "Force removal may leave residual files in /lib/modules/"
                        if confirm "Force remove ${pkg}?"; then
                            run_sudo dpkg --purge --force-remove-reinstreq "${pkg}" || warn "Failed to remove ${pkg}"
                        else
                            warn "Skipped force removal of ${pkg}. You may need to fix it manually:"
                            warn "  sudo dpkg --purge --force-remove-reinstreq ${pkg}"
                        fi
                    fi
                elif dpkg -l "${pkg}" 2>/dev/null | grep -q "^rc"; then
                    log "Purging config files for ${pkg}..."
                    run_sudo dpkg --purge "${pkg}" || warn "Failed to purge ${pkg}"
                fi
            done
        elif [[ "${PKG_MANAGER}" = "dnf" ]]; then
            for pkg in "${packages[@]}"; do
                if rpm -q "${pkg}" &>/dev/null 2>&1; then
                    log "Removing ${pkg}..."
                    run_sudo dnf remove -y "${pkg}" || warn "Failed to remove ${pkg}"
                fi
            done
        fi
    fi

    if confirm "Remove Podman packages (podman, podman-docker, podman-compose)?"; then
        if [[ "${PKG_MANAGER}" = "apt-get" ]]; then
            for pkg in "${podman_packages[@]}"; do
                if dpkg -l "${pkg}" 2>/dev/null | grep -q "^ii"; then
                    log "Removing ${pkg}..."
                    run_sudo apt-get purge -y "${pkg}" || warn "Failed to remove ${pkg}"
                elif dpkg -l "${pkg}" 2>/dev/null | grep -q "^rc"; then
                    log "Purging config files for ${pkg}..."
                    run_sudo dpkg --purge "${pkg}" || warn "Failed to purge ${pkg}"
                fi
            done
        elif [[ "${PKG_MANAGER}" = "dnf" ]]; then
            for pkg in "${podman_packages[@]}"; do
                if rpm -q "${pkg}" &>/dev/null 2>&1; then
                    log "Removing ${pkg}..."
                    run_sudo dnf remove -y "${pkg}" || warn "Failed to remove ${pkg}"
                fi
            done
        fi
    fi
}

# Remove apt/dnf repository configuration
remove_repo_config() {
    log "Removing Tenstorrent repository configuration..."

    if [[ "${PKG_MANAGER}" = "apt-get" ]]; then
        local apt_files=(
            "/etc/apt/sources.list.d/tenstorrent.list"
            "/etc/apt/keyrings/tt-pkg-key.asc"
        )

        for f in "${apt_files[@]}"; do
            if [[ -f "${f}" ]]; then
                log "Removing ${f}"
                run_sudo rm -f "${f}"
            fi
        done

        if [[ "${DRY_RUN}" -eq 0 ]]; then
            log "Updating apt cache..."
            run_sudo apt-get update || warn "apt-get update failed"
        fi
    elif [[ "${PKG_MANAGER}" = "dnf" ]]; then
        if [[ -f "/etc/yum.repos.d/tenstorrent.repo" ]]; then
            log "Removing /etc/yum.repos.d/tenstorrent.repo"
            run_sudo rm -f "/etc/yum.repos.d/tenstorrent.repo"
        fi
    fi
}

show_help() {
    cat << EOF
Tenstorrent Uninstaller

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -n, --dry-run           Show what would be removed without actually removing
    -f, --force             Don't ask for confirmation
    --keep-venv             Keep the Python virtual environment
    --keep-system-packages  Keep system packages (tenstorrent-dkms, etc.)
    --venv-path PATH        Custom venv path (default: ~/.tenstorrent-venv)

Examples:
    $0                      Interactive uninstall
    $0 --dry-run            See what would be removed
    $0 --force              Remove everything without confirmation
    $0 --keep-venv          Remove everything except the Python venv
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -f|--force)
                FORCE=1
                shift
                ;;
            --keep-venv)
                KEEP_VENV=1
                shift
                ;;
            --keep-system-packages)
                KEEP_SYSTEM_PACKAGES=1
                shift
                ;;
            --venv-path)
                VENV_PATH="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    echo -e "${LOGO}"
    echo

    parse_args "$@"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        warn "Running in DRY-RUN mode - no changes will be made"
        echo
    fi

    log "This script will remove Tenstorrent software installed by tt-installer"
    echo

    if ! confirm "Continue with uninstallation?"; then
        log "Uninstallation cancelled"
        exit 0
    fi

    detect_distro
    log "Detected distribution: ${DISTRO_ID} (package manager: ${PKG_MANAGER})"
    echo

    # Remove in reverse order of installation
    remove_venv_alias
    remove_wrapper_scripts
    remove_repositories
    remove_podman_images
    remove_python_packages
    remove_venv
    remove_system_packages
    remove_repo_config

    echo
    log "Uninstallation completed!"

    if [[ "${DRY_RUN}" -eq 0 ]]; then
        warn "You may need to reboot for kernel driver changes to take effect"
        warn "Please open a new terminal for shell RC changes to take effect"
        echo
        log "To remove unused dependencies, run: sudo apt autoremove"
        log "(Review the package list before confirming)"
    fi
}

main "$@"
