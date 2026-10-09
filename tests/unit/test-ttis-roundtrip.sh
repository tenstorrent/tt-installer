#!/usr/bin/env bash
# Regression test for issue #171.
#
# A disabled package can still carry a version pin (for example after
# --no-install-kmd --kmd-version 2.9.0). Schema v1 records "not installed" as
# an empty version string, and ttis_import treats every non-empty value as
# installed, so the export must not write the pin - otherwise replaying the
# file silently re-enables the package.
#
# Usage: bash tests/unit/test-ttis-roundtrip.sh
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# Globals that ttis.sh reads from the caller's scope.
# shellcheck disable=SC2034
DISTRO_ID=ubuntu
# shellcheck disable=SC2034
VERSION_ID=24.04
# shellcheck disable=SC2034
PKG_MANAGER=apt-get
# shellcheck disable=SC2034
INSTALLER_VERSION="test"
# shellcheck disable=SC2034
TTIS_VERBOSE=0

# Declared so the assertions below are resolvable; ttis_import fills them in.
_arg_install_kmd=""
_arg_kmd_version=""
_arg_install_hugepages=""
_arg_systools_version=""
_arg_install_tt_smi=""
_arg_smi_version=""
_arg_install_tt_flash=""
_arg_flash_version=""

# shellcheck disable=SC1091
source "${ROOT}/ttis.sh"

# shellcheck disable=SC2034
declare -A package_registry=(
	[tenstorrent-dkms]="tenstorrent-dkms|off|1.2.3|system"
	[tenstorrent-tools]="tenstorrent-tools|on|2.3.4|system"
	[sfpi]="sfpi|off||system"
	[tt-smi]="tt-smi|off|3.4.5|python"
	[tt-flash]="tt-flash|on|4.5.6|python"
)

workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT
state="${workdir}/state.ttis"

ttis_export "${state}" >/dev/null

# Disabled packages export an empty version; enabled packages keep their pins.
[[ "$(jq -r '.tt_system["tenstorrent-dkms"]' "${state}")" == "" ]]
[[ "$(jq -r '.tt_python["tt-smi"]' "${state}")" == "" ]]
[[ "$(jq -r '.tt_system["tenstorrent-tools"]' "${state}")" == "2.3.4" ]]
[[ "$(jq -r '.tt_python["tt-flash"]' "${state}")" == "4.5.6" ]]

# Replaying the exported state must leave the disabled packages disabled.
unset package_registry
ttis_import "${state}" >/dev/null

[[ "${_arg_install_kmd}" == "off" ]]
[[ "${_arg_kmd_version}" == "" ]]
[[ "${_arg_install_tt_smi}" == "off" ]]
[[ "${_arg_smi_version}" == "" ]]
[[ "${_arg_install_hugepages}" == "on" ]]
[[ "${_arg_systools_version}" == "2.3.4" ]]
[[ "${_arg_install_tt_flash}" == "on" ]]
[[ "${_arg_flash_version}" == "4.5.6" ]]

echo "PASS: disabled packages stay disabled across export/import"
