#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="${ROOT}/install.sh"
FIXTURES="${ROOT}/tests/fixtures"

[[ -f "${INSTALLER}" ]] || {
	echo "install.sh is missing; run 'make install.sh' first" >&2
	exit 1
}

tmp_root=$(mktemp -d)
trap 'rm -rf "${tmp_root}"' EXIT
stub_bin="${tmp_root}/bin"
home="${tmp_root}/home"
tmp_dir="${tmp_root}/tmp"
mkdir -p "${stub_bin}" "${home}/.local/bin" "${home}/.local/lib" "${tmp_dir}"
printf '%s\n' sentinel > "${home}/.local/bin/sentinel"
printf '%s\n' sentinel > "${home}/.local/lib/sentinel"
printf '%s\n' sentinel > "${home}/.tenstorrent-venv"
forbidden_log="${tmp_root}/forbidden.log"

for command_name in sudo apt apt-get dnf dkms modprobe tt-flash reboot systemctl \
	usermod groupadd pip pip3 pipx uv git wget ssh scp nc ncat rpm; do
	cat > "${stub_bin}/${command_name}" <<'EOF'
#!/usr/bin/env bash
printf '%s %q\n' "$(basename "$0")" "$*" >> "${FORBIDDEN_LOG}"
exit 97
EOF
	chmod +x "${stub_bin}/${command_name}"
done

for command_name in docker podman; do
	cat > "${stub_bin}/${command_name}" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" = "--version" || "${1:-}" = "info" ]]; then
	exit 0
fi
printf '%s %q\n' "$(basename "$0")" "$*" >> "${FORBIDDEN_LOG}"
exit 97
EOF
	chmod +x "${stub_bin}/${command_name}"
done

cat > "${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=""
output=""
previous=""
for arg in "$@"; do
	if [[ "${previous}" = "-o" ]]; then
		output="${arg}"
		previous=""
		continue
	fi
	case "${arg}" in
		-o) previous="-o" ;;
		-O) output="$(basename "${url}")" ;;
		https://*) url="${arg}" ;;
	esac
done
case "${url}" in
	*ubuntu-24.04.ttis) source_file="${FIXTURES}/dry-run-apt.ttis" ;;
	*fedora-42.ttis) source_file="${FIXTURES}/dry-run-dnf.ttis" ;;
	https://api.github.com/*)
		printf 'HTTP/2 200\r\nx-ratelimit-remaining: 100\r\n\r\n%s\n' '{"tag_name":"v1.2.3"}'
		exit 0
		;;
	*) exit 97 ;;
esac
if [[ -n "${output}" ]]; then
	cp "${source_file}" "${output}"
else
	cat "${source_file}"
fi
EOF
chmod +x "${stub_bin}/curl"

run_installer() {
	local os_release="$1"
	shift
	HOME="${home}" TMPDIR="${tmp_dir}" PATH="${stub_bin}:${PATH}" \
	TT_INSTALLER_OS_RELEASE="${os_release}" FORBIDDEN_LOG="${forbidden_log}" FIXTURES="${FIXTURES}" \
		bash "${INSTALLER}" "$@"
}

assert_output() {
	local output="$1"
	local pattern="$2"
	[[ "${output}" == *"${pattern}"* ]] || {
		echo "missing output pattern: ${pattern}" >&2
		return 1
	}
}

assert_no_mutation() {
	[[ ! -s "${forbidden_log}" ]] || {
		cat "${forbidden_log}" >&2
		return 1
	}
	[[ ! -e "${home}/.local/bin/tt-metalium" ]]
	[[ ! -e "${home}/.local/bin/tt-metalium-models" ]]
	[[ ! -e "${home}/.local/bin/tt-forge" ]]
	[[ ! -e "${home}/.local/bin/tt-studio" ]]
	[[ ! -e "${home}/.local/bin/tt-inference-server" ]]
	[[ ! -e "${home}/.local/lib/tt-studio" ]]
	[[ ! -e "${home}/.local/lib/tt-inference-server" ]]
	[[ ! -e "${home}/custom-metalium" ]]
	[[ ! -e "${home}/custom-forge" ]]
	[[ ! -e "${home}/export.ttis" ]]
	[[ -f "${home}/.local/bin/sentinel" ]]
	[[ -f "${home}/.local/lib/sentinel" ]]
	[[ -f "${home}/.tenstorrent-venv" ]]
	# The installer-owned directory must be removed. Some jq/libc builds may
	# leave unrelated dot-temporary files directly under TMPDIR, so scope this
	# assertion to the installer's tenstorrent_install_* namespace.
	local leftover
	leftover=$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -name 'tenstorrent_install_*' -print -quit)
	[[ -z "${leftover}" ]]
}

help_output=$(bash "${INSTALLER}" --help)
assert_output "${help_output}" "--dry-run"

output=$(run_installer "${FIXTURES}/os-release-ubuntu-24.04" \
	--dry-run --versions "${FIXTURES}/dry-run-apt.ttis" --export-schema "${home}/export.ttis" \
	--metalium-container-script-dir "${home}/custom-metalium" \
	--forge-container-script-dir "${home}/custom-forge")
assert_output "${output}" "==== DRY-RUN: Installation Preview ===="
assert_output "${output}" "Action execution: suppressed"
assert_output "${output}" "Platform: ubuntu 24.04 (apt-get)"
assert_output "${output}" "Architecture:"
assert_output "${output}" "Kernel:"
assert_output "${output}" "extra-system=2.3.4"
assert_output "${output}" "extra-python==2.3.4"
assert_output "${output}" "Firmware: force-flash 1.2.3"
assert_output "${output}" "Privileged operations: suppressed"
assert_output "${output}" "Export: suppressed"
assert_no_mutation

output=$(run_installer "${FIXTURES}/os-release-ubuntu-24.04" \
	--dry-run --versions release --update-firmware off)
assert_output "${output}" "==== DRY-RUN: Installation Preview ===="
assert_output "${output}" "tenstorrent-dkms=1.2.3"
assert_no_mutation

output=$(run_installer "${FIXTURES}/os-release-fedora-42" \
	--dry-run --versions "${FIXTURES}/dry-run-dnf.ttis")
assert_output "${output}" "Platform: fedora 42 (dnf)"
assert_output "${output}" "extra-system-2.3.4"
assert_output "${output}" "extra-python==2.3.4"
assert_output "${output}" "Containers: runtime=podman"
assert_no_mutation

output=$(run_installer "${FIXTURES}/os-release-ubuntu-24.04" \
	--dry-run --versions rolling --update-firmware on --pull-container-images \
	--install-metalium-models-container --install-forge-container --reboot-option always)
assert_output "${output}" "Version channel: rolling"
assert_output "${output}" "Firmware: update 1.2.3"
assert_output "${output}" "Metalium image:"
assert_output "${output}" "Metalium Models image:"
assert_output "${output}" "Forge image:"
assert_output "${output}" "pull during install"
assert_output "${output}" "Reboot: suppressed (always)"
assert_no_mutation

output=$(run_installer "${FIXTURES}/os-release-ubuntu-24.04" \
	--dry-run --versions rolling --mode-container --update-firmware off)
assert_output "${output}" "HugePages: off"
assert_output "${output}" "Containers: runtime=none"
assert_output "${output}" "Reboot: suppressed (never)"
assert_no_mutation

output=$(run_installer "${FIXTURES}/os-release-ubuntu-24.04" \
	--dry-run --versions rolling --update-firmware off \
	--no-install-metalium-container --no-install-metalium-models-container \
	--no-install-forge-container)
assert_output "${output}" "Containers: runtime=none"
assert_no_mutation

expect_failure() {
	echo "expected failure: $*"
	if run_installer "${FIXTURES}/os-release-ubuntu-24.04" "$@" >/dev/null 2>&1; then
		echo "did not fail as expected: $*" >&2
		return 1
	fi
}

expect_failure --dry-run --versions rolling --install-container-runtime invalid
expect_failure --dry-run --versions rolling --update-firmware invalid
expect_failure --dry-run --versions rolling --python-choice invalid
expect_failure --dry-run --versions "${FIXTURES}/wrong-family.ttis"
expect_failure --dry-run --versions "${tmp_root}/missing.ttis"
expect_failure --dry-run --versions "${FIXTURES}/invalid-json.ttis"
expect_failure --dry-run --versions "${FIXTURES}/future-schema.ttis"
expect_failure --dry-run --versions "${FIXTURES}/invalid-runtime.ttis"
expect_failure --dry-run --versions "${FIXTURES}/invalid-python-strategy.ttis"
[[ -z "$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -name 'tenstorrent_install_*' -print -quit)" ]]

echo "expected failure: invalid JSON fixture"
if bash "${ROOT}/ttis.sh" validate "${FIXTURES}/invalid-json.ttis" >/dev/null 2>&1; then exit 1; fi
echo "expected failure: future schema fixture"
if bash "${ROOT}/ttis.sh" validate "${FIXTURES}/future-schema.ttis" >/dev/null 2>&1; then exit 1; fi
echo "expected failure: invalid runtime fixture"
if bash "${ROOT}/ttis.sh" validate "${FIXTURES}/invalid-runtime.ttis" >/dev/null 2>&1; then exit 1; fi
echo "expected failure: invalid Python strategy fixture"
if bash "${ROOT}/ttis.sh" validate "${FIXTURES}/invalid-python-strategy.ttis" >/dev/null 2>&1; then exit 1; fi

echo "expected failure: INSTALLER_SOURCE_ONLY must not run the installer"
if INSTALLER_SOURCE_ONLY=1 bash "${INSTALLER}" --dry-run >/dev/null 2>&1; then exit 1; fi

echo -e "\033[0;32mTests passed!\033[0m"
