#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
INSTALLER="${ROOT}/install.sh"
[[ -f "${INSTALLER}" ]] || { echo "install.sh is missing" >&2; exit 1; }

export INSTALLER_SOURCE_ONLY=1
# shellcheck disable=SC1090
source "${INSTALLER}"

_arg_install_container_runtime=auto
_arg_update_firmware=force
_arg_python_choice=new-venv
_arg_reboot_option=ask
_arg_mode_container=on
_arg_install_kmd=on
_arg_install_hugepages=on
_arg_install_sfpi=on
normalize_options
[[ "${_arg_install_container_runtime}" = none ]]
[[ "${_arg_install_kmd}" = off ]]
[[ "${_arg_install_hugepages}" = off ]]
[[ "${_arg_install_sfpi}" = off ]]
[[ "${_arg_reboot_option}" = never ]]

_arg_install_container_runtime=none
_arg_mode_container=off
_arg_install_kmd=on
_arg_install_hugepages=on
_arg_install_sfpi=on
normalize_options
# These globals are consumed by functions sourced from the generated script.
# shellcheck disable=SC2034
DISTRO_ID=ubuntu
# shellcheck disable=SC2034
PKG_MANAGER=apt-get
resolve_base_packages
[[ "${BASE_SYSTEM_PACKAGES[*]}" = *"cargo rustc"* ]]

_arg_kmd_version=1.2.3
_arg_systools_version=2.3.4
_arg_sfpi_version=""
_arg_smi_version=3.4.5
_arg_flash_version=""
# shellcheck disable=SC2034
TTIS_IMPORTED_PACKAGES=("extra-system|on|4.5.6|system" "extra-python|on|5.6.7|python")
build_package_registry
resolve_package_actions
[[ "${SYSTEM_PACKAGES[*]}" = *"tenstorrent-dkms=1.2.3"* ]]
[[ "${SYSTEM_PACKAGES[*]}" = *"extra-system=4.5.6"* ]]
[[ "${PYTHON_PACKAGES[*]}" = *"tt-smi==3.4.5"* ]]
[[ "${PYTHON_PACKAGES[*]}" = *"extra-python==5.6.7"* ]]

old_path="${PATH}"
# shellcheck disable=SC2123
PATH=/nonexistent
_arg_install_container_runtime=auto
resolve_container_runtime
PATH="${old_path}"
[[ "${RESOLVED_CONTAINER_RUNTIME}" = docker ]]
[[ "${CONTAINER_RUNTIME_PRESENT}" = 0 ]]

PKG_MANAGER=dnf
resolve_package_actions
[[ "${SYSTEM_PACKAGES[*]}" = *"tenstorrent-dkms-1.2.3"* ]]
# shellcheck disable=SC2034
PKG_MANAGER=apt-get

_arg_update_firmware=off
resolve_firmware_action
[[ "${RESOLVED_FIRMWARE_ACTION}" = skip ]]
_arg_update_firmware=on
resolve_firmware_action
[[ "${RESOLVED_FIRMWARE_ACTION}" = update ]]
_arg_update_firmware=force
resolve_firmware_action
[[ "${RESOLVED_FIRMWARE_ACTION}" = force-flash ]]

# --- normalize_options: backward-compat "no" and invalid values ---
_arg_install_container_runtime=no
_arg_mode_container=off
normalize_options
[[ "${_arg_install_container_runtime}" = none ]]

expect_fail() {
	echo "expected failure: $1"
	shift
	if "$@"; then
		echo "did not fail as expected: $*" >&2
		exit 1
	fi
}

_arg_install_container_runtime=invalid
expect_fail "invalid container runtime" normalize_options
_arg_install_container_runtime=auto

_arg_update_firmware=invalid
expect_fail "invalid firmware option" normalize_options
_arg_update_firmware=force

_arg_python_choice=conda
expect_fail "invalid Python strategy" normalize_options
_arg_python_choice=new-venv

_arg_reboot_option=maybe
expect_fail "invalid reboot option" normalize_options
_arg_reboot_option=ask

# --- resolve_base_packages: every distro branch ---
for d in ubuntu debian fedora rhel centos; do
	DISTRO_ID="${d}"
	resolve_base_packages
	[[ "${#BASE_SYSTEM_PACKAGES[@]}" -gt 0 ]]
	if [[ "${d}" = rhel || "${d}" = centos ]]; then
		[[ "${BASE_BOOTSTRAP_PACKAGES[*]}" = epel-release ]]
		[[ "${BASE_SYSTEM_PACKAGES[*]}" != *epel-release* ]]
	else
		[[ "${#BASE_BOOTSTRAP_PACKAGES[@]}" -eq 0 ]]
	fi
done
DISTRO_ID=arch
expect_fail "unsupported distribution" resolve_base_packages
DISTRO_ID=ubuntu
resolve_base_packages

# --- resolve_package_actions: bare names and off flags ---
_arg_install_kmd=off
_arg_systools_version=""
_arg_install_tt_smi=on
_arg_smi_version=""
_arg_install_tt_flash=off
_arg_install_sfpi=on
_arg_sfpi_version=""
# shellcheck disable=SC2034
TTIS_IMPORTED_PACKAGES=()
build_package_registry
resolve_package_actions
[[ "${SYSTEM_PACKAGES[*]}" = *"sfpi"* ]]
[[ "${SYSTEM_PACKAGES[*]}" != *"tenstorrent-dkms"* ]]
[[ "${PYTHON_PACKAGES[*]}" = *"tt-smi"* ]]
[[ "${PYTHON_PACKAGES[*]}" != *"tt-flash"* ]]
[[ "${SYSTEM_PACKAGES[*]}" = "$(printf '%s\n' "${SYSTEM_PACKAGES[@]}" | LC_ALL=C sort | paste -sd ' ' -)" ]]
[[ "${PYTHON_PACKAGES[*]}" = "$(printf '%s\n' "${PYTHON_PACKAGES[@]}" | LC_ALL=C sort | paste -sd ' ' -)" ]]

# --- resolve_container_runtime: stubbed environments ---
docker_bin=$(mktemp -d)
cat > "${docker_bin}/docker" <<'STUB'
#!/bin/bash
[[ "${1:-}" = "info" ]] && exit 1
exit 0
STUB
chmod +x "${docker_bin}/docker"
podman_bin=$(mktemp -d)
cat > "${podman_bin}/podman" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "${podman_bin}/podman"
podman_shim_bin=$(mktemp -d)
cat > "${podman_shim_bin}/docker" <<'STUB'
#!/bin/bash
printf '%s\n' 'podman version 5.0.0'
STUB
cat > "${podman_shim_bin}/podman" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "${podman_shim_bin}/docker" "${podman_shim_bin}/podman"
old_path="${PATH}"

PATH="${docker_bin}"
_arg_install_container_runtime=auto
resolve_container_runtime
[[ "${RESOLVED_CONTAINER_RUNTIME}" = docker ]]
[[ "${CONTAINER_RUNTIME_PRESENT}" = 1 ]]
[[ "${CONTAINER_PULL_PREFIX}" = sudo ]]
[[ "${CONTAINER_CLI}" = docker ]]

_arg_install_container_runtime=docker
resolve_container_runtime
[[ "${RESOLVED_CONTAINER_RUNTIME}" = docker ]]
[[ "${CONTAINER_RUNTIME_PRESENT}" = 1 ]]

_arg_install_container_runtime=none
resolve_container_runtime
[[ "${RESOLVED_CONTAINER_RUNTIME}" = none ]]
[[ "${CONTAINER_RUNTIME_PRESENT}" = 1 ]]
[[ "${CONTAINER_CLI}" = docker ]]
[[ "${CONTAINER_PULL_PREFIX}" = sudo ]]

PATH="${podman_bin}"
_arg_install_container_runtime=auto
resolve_container_runtime
[[ "${RESOLVED_CONTAINER_RUNTIME}" = podman ]]
[[ "${CONTAINER_RUNTIME_PRESENT}" = 1 ]]
[[ "${CONTAINER_CLI}" = podman ]]

PATH="${podman_shim_bin}"
_arg_install_container_runtime=auto
resolve_container_runtime
[[ "${RESOLVED_CONTAINER_RUNTIME}" = podman ]]
[[ "${CONTAINER_RUNTIME_PRESENT}" = 1 ]]
[[ "${CONTAINER_CLI}" = podman ]]

PATH="${old_path}"
rm -rf "${docker_bin}" "${podman_bin}" "${podman_shim_bin}"

_arg_install_container_runtime=auto
_arg_install_metalium_container=off
_arg_install_metalium_models_container=off
_arg_install_forge_container=off
disable_unused_container_runtime
[[ "${_arg_install_container_runtime}" = none ]]

# --- render_install_plan: deterministic preview ---
# shellcheck disable=SC2034
declare DISTRO_ID=ubuntu VERSION_ID=24.04 PKG_MANAGER=apt-get
# shellcheck disable=SC2034
declare -a BASE_SYSTEM_PACKAGES=(git jq)
# shellcheck disable=SC2034
declare -a BASE_BOOTSTRAP_PACKAGES=()
# shellcheck disable=SC2034
declare -a SYSTEM_PACKAGES=(sfpi=1.2.3)
# shellcheck disable=SC2034
declare -a PYTHON_PACKAGES=(tt-smi==1.2.3)
# shellcheck disable=SC2034
declare RESOLVED_FIRMWARE_ACTION=force-flash RESOLVED_CONTAINER_RUNTIME=docker CONTAINER_RUNTIME_PRESENT=1
# shellcheck disable=SC2034
declare CONTAINER_CLI=docker
# shellcheck disable=SC2034
declare _arg_fw_version=1.2.3 _arg_install_hugepages=on \
	_arg_metalium_image_url=ghcr.io/tenstorrent/tt-metal _arg_metalium_image_tag=latest \
	_arg_install_metalium_container=on _arg_install_metalium_models_container=off \
	_arg_forge_image_url=ghcr.io/tenstorrent/tt-xla _arg_forge_image_tag=latest \
	_arg_install_forge_container=off _arg_install_inference_server=on \
	_arg_install_studio=on _arg_python_choice=new-venv _arg_reboot_option=never \
	_arg_pull_container_images=on _arg_export_schema=
plan=$(TT_INSTALLER_ARCH=x86_64 TT_INSTALLER_KERNEL=6.0.0-test render_install_plan)
[[ "${plan}" == *"Platform: ubuntu 24.04 (apt-get)"* ]]
[[ "${plan}" == *"Architecture: x86_64"* ]]
[[ "${plan}" == *"Kernel: 6.0.0-test"* ]]
[[ "${plan}" == *"TT system packages: sfpi=1.2.3"* ]]
[[ "${plan}" == *"Python packages: tt-smi==1.2.3"* ]]
[[ "${plan}" == *"Firmware: force-flash 1.2.3"* ]]
[[ "${plan}" == *"Containers: runtime=docker present=1"* ]]
[[ "${plan}" == *"Metalium image:"*"(pull during install)"* ]]
[[ "${plan}" == *"Metalium Models image:"*"(disabled)"* ]]
[[ "${plan}" == *"Export: suppressed"* ]]

RESOLVED_CONTAINER_RUNTIME=none
CONTAINER_RUNTIME_PRESENT=0
CONTAINER_CLI=""
plan=$(TT_INSTALLER_ARCH=x86_64 TT_INSTALLER_KERNEL=6.0.0-test render_install_plan)
[[ "${plan}" == *"Metalium image: ghcr.io/tenstorrent/tt-metal:latest (disabled)"* ]]

echo -e "\033[0;32mTests passed!\033[0m"
