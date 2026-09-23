#!/usr/bin/env bash
# Tests for the two-phase offline install:
#   --prepare-offline-bundle DIR  (download firmware, never flash)
#   --offline-bundle DIR          (flash from DIR, never touch the network)
#
# Every network-capable or privileged command is stubbed. curl always fails
# and records the call, so any offline-bundle run that reaches for the network
# both aborts the installer and leaves evidence in the forbidden log.
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
mkdir -p "${stub_bin}" "${home}" "${tmp_dir}"
forbidden_log="${tmp_root}/forbidden.log"
flash_log="${tmp_root}/tt-flash.log"

# Commands the offline path must never run.
for command_name in sudo apt apt-get dnf dkms modprobe reboot systemctl \
	usermod groupadd pip pip3 pipx uv git wget docker podman curl; do
	cat > "${stub_bin}/${command_name}" <<'EOF'
#!/usr/bin/env bash
printf '%s %q\n' "$(basename "$0")" "$*" >> "${FORBIDDEN_LOG}"
exit 97
EOF
	chmod +x "${stub_bin}/${command_name}"
done

# A recording tt-flash that succeeds. It lives in its own directory so tests
# can control whether it is on PATH directly or only via a recorded venv.
flash_bin="${tmp_root}/flash-bin"
mkdir -p "${flash_bin}"
cat > "${flash_bin}/tt-flash" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FLASH_LOG}"
exit 0
EOF
chmod +x "${flash_bin}/tt-flash"

run_installer() {
	local extra_path="$1"
	shift
	HOME="${home}" TMPDIR="${tmp_dir}" PATH="${stub_bin}:${extra_path}${extra_path:+:}${PATH}" \
	TT_INSTALLER_OS_RELEASE="${FIXTURES}/os-release-ubuntu-24.04" \
	FORBIDDEN_LOG="${forbidden_log}" FLASH_LOG="${flash_log}" \
		bash "${INSTALLER}" "$@"
}

assert_output() {
	[[ "$1" == *"$2"* ]] || {
		echo "missing output pattern: $2" >&2
		echo "--- output ---" >&2
		echo "$1" >&2
		return 1
	}
}

assert_no_forbidden() {
	[[ ! -s "${forbidden_log}" ]] || {
		echo "forbidden command executed:" >&2
		cat "${forbidden_log}" >&2
		return 1
	}
}

reset_logs() {
	: > "${forbidden_log}"
	: > "${flash_log}"
}

# Build a valid bundle directory: the .ttis state export plus the firmware
# file it names. Starts from the dry-run fixture (firmware 1.2.3, apt family)
# and overrides the Python environment.
make_bundle() {
	local dir="$1" py_method="${2:-venv}" py_location="${3:-}"
	mkdir -p "${dir}"
	printf 'not really firmware\n' > "${dir}/fw_pack-1.2.3.fwbundle"
	jq --arg m "${py_method}" --arg l "${py_location}" \
		'.python_env = {method: $m, location: $l, python_version: ""}' \
		"${FIXTURES}/dry-run-apt.ttis" > "${dir}/tt-installer-state.ttis"
}

help_output=$(bash "${INSTALLER}" --help)
assert_output "${help_output}" "--prepare-offline-bundle"
assert_output "${help_output}" "--offline-bundle"

# ── --offline-bundle: dry-run shows the plan, runs nothing ──
echo "offline dry-run"
reset_logs
bundle="${tmp_root}/bundle"
make_bundle "${bundle}"
output=$(run_installer "${flash_bin}" --dry-run --offline-bundle "${bundle}")
assert_output "${output}" "==== DRY-RUN: Offline Flash Preview ===="
assert_output "${output}" "Platform: ubuntu 24.04 (apt-get)"
assert_output "${output}" "Offline bundle: ${bundle}"
assert_output "${output}" "State file: ${bundle}/tt-installer-state.ttis"
assert_output "${output}" "Firmware: force-flash 1.2.3 (${bundle}/fw_pack-1.2.3.fwbundle)"
assert_output "${output}" "tt-flash: ${flash_bin}/tt-flash"
assert_output "${output}" "Network access: none"
assert_output "${output}" "Reboot: suppressed (never)"
assert_no_forbidden
[[ ! -s "${flash_log}" ]]
[[ -z "$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -name 'tenstorrent_install_*' -print -quit)" ]]

# ── --offline-bundle: real run flashes with --force and nothing else ──
echo "offline flash (force)"
reset_logs
output=$(run_installer "${flash_bin}" --offline-bundle "${bundle}" --mode-non-interactive)
assert_output "${output}" "only the firmware flash will run"
assert_output "${output}" "Firmware flash completed successfully"
assert_no_forbidden
[[ "$(cat "${flash_log}")" == "flash ${bundle}/fw_pack-1.2.3.fwbundle --force" ]]

# ── importing the state file must not swallow the user's reboot prompt ──
# (read -p only echoes its prompt on a tty, so assert on behaviour: "y" must
# reach the sudo stub, "n" must not.)
echo "offline flash (interactive reboot prompt)"
reset_logs
printf 'n\n' | run_installer "${flash_bin}" --offline-bundle "${bundle}" --reboot-option ask > /dev/null
assert_no_forbidden
[[ "$(cat "${flash_log}")" == "flash ${bundle}/fw_pack-1.2.3.fwbundle --force" ]]
reset_logs
# The sudo stub fails, so the installer exits non-zero after attempting the reboot.
printf 'y\n' | run_installer "${flash_bin}" --offline-bundle "${bundle}" --reboot-option ask > /dev/null 2>&1 || true
[[ "$(cat "${forbidden_log}")" == "sudo reboot" ]]

# ── --update-firmware=on drops --force ──
echo "offline flash (update)"
reset_logs
run_installer "${flash_bin}" --offline-bundle "${bundle}" --mode-non-interactive --update-firmware on > /dev/null
assert_no_forbidden
[[ "$(cat "${flash_log}")" == "flash ${bundle}/fw_pack-1.2.3.fwbundle" ]]

# ── relative bundle path is resolved against the working directory ──
echo "offline flash (relative path)"
reset_logs
(cd "${tmp_root}" && run_installer "${flash_bin}" --offline-bundle bundle --mode-non-interactive > /dev/null)
assert_no_forbidden
[[ "$(cat "${flash_log}")" == "flash ${bundle}/fw_pack-1.2.3.fwbundle --force" ]]

# ── tt-flash found only through the venv recorded in the manifest ──
echo "offline flash (venv from manifest)"
reset_logs
venv="${tmp_root}/venv"
mkdir -p "${venv}/bin"
cp "${flash_bin}/tt-flash" "${venv}/bin/tt-flash"
echo "export PATH=\"${venv}/bin:\${PATH}\"" > "${venv}/bin/activate"
venv_bundle="${tmp_root}/venv-bundle"
make_bundle "${venv_bundle}" venv "${venv}"
output=$(run_installer "" --offline-bundle "${venv_bundle}" --mode-non-interactive)
assert_output "${output}" "Activating Python environment recorded in the bundle: ${venv}"
assert_no_forbidden
[[ "$(cat "${flash_log}")" == "flash ${venv_bundle}/fw_pack-1.2.3.fwbundle --force" ]]

# ── recorded venv missing and tt-flash not on PATH: clear failure, no network ──
echo "offline flash (tt-flash unavailable)"
reset_logs
gone_bundle="${tmp_root}/gone-bundle"
make_bundle "${gone_bundle}" venv "${tmp_root}/does-not-exist"
if output=$(run_installer "" --offline-bundle "${gone_bundle}" --mode-non-interactive 2>&1); then
	echo "expected failure when tt-flash is unavailable" >&2
	exit 1
fi
assert_output "${output}" "was not found at ${tmp_root}/does-not-exist"
assert_output "${output}" "tt-flash is not installed or not in PATH"
assert_no_forbidden
[[ ! -s "${flash_log}" ]]

# ── invalid bundles are rejected before anything runs ──
expect_failure() {
	local pattern="$1"
	shift
	echo "expected failure: $*"
	reset_logs
	local output
	if output=$(run_installer "${flash_bin}" "$@" 2>&1); then
		echo "did not fail as expected: $*" >&2
		return 1
	fi
	assert_output "${output}" "${pattern}"
	assert_no_forbidden
	[[ ! -s "${flash_log}" ]]
}

expect_failure "Offline bundle directory not found" \
	--offline-bundle "${tmp_root}/missing" --mode-non-interactive
empty_bundle="${tmp_root}/empty-bundle"
mkdir -p "${empty_bundle}"
expect_failure "No tt-installer-state.ttis in ${empty_bundle}" \
	--offline-bundle "${empty_bundle}" --mode-non-interactive
bad_json_bundle="${tmp_root}/bad-json-bundle"
make_bundle "${bad_json_bundle}"
cp "${FIXTURES}/invalid-json.ttis" "${bad_json_bundle}/tt-installer-state.ttis"
expect_failure "not valid JSON" \
	--offline-bundle "${bad_json_bundle}" --mode-non-interactive
future_bundle="${tmp_root}/future-bundle"
make_bundle "${future_bundle}"
cp "${FIXTURES}/future-schema.ttis" "${future_bundle}/tt-installer-state.ttis"
expect_failure "unsupported schema_version" \
	--offline-bundle "${future_bundle}" --mode-non-interactive
family_bundle="${tmp_root}/family-bundle"
make_bundle "${family_bundle}"
cp "${FIXTURES}/wrong-family.ttis" "${family_bundle}/tt-installer-state.ttis"
expect_failure "distro family mismatch" \
	--offline-bundle "${family_bundle}" --mode-non-interactive
nofw_bundle="${tmp_root}/nofw-bundle"
make_bundle "${nofw_bundle}"
jq '.firmware.version = ""' "${nofw_bundle}/tt-installer-state.ttis" > "${nofw_bundle}/s.ttis" \
	&& mv "${nofw_bundle}/s.ttis" "${nofw_bundle}/tt-installer-state.ttis"
expect_failure "records no firmware version" \
	--offline-bundle "${nofw_bundle}" --mode-non-interactive
nofile_bundle="${tmp_root}/nofile-bundle"
make_bundle "${nofile_bundle}"
rm "${nofile_bundle}/fw_pack-1.2.3.fwbundle"
expect_failure "Firmware bundle for version 1.2.3 not found at ${nofile_bundle}/fw_pack-1.2.3.fwbundle" \
	--offline-bundle "${nofile_bundle}" --mode-non-interactive
expect_failure "leaves nothing to do" \
	--offline-bundle "${bundle}" --mode-non-interactive --update-firmware off
expect_failure "mutually exclusive" \
	--offline-bundle "${bundle}" --prepare-offline-bundle "${tmp_root}/x" --mode-non-interactive

# ── --prepare-offline-bundle: dry-run plan says download-only, writes nothing ──
echo "prepare dry-run"
reset_logs
# The full-install planner probes the container runtime read-only; allow
# those two calls, as the dry-run suite does. (The offline runs above kept the
# strict stubs, proving --offline-bundle never probes a runtime at all.)
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
# Restore a curl that serves the golden file and release metadata, as the
# dry-run suite does, so the plan can resolve versions.
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
		https://*) url="${arg}" ;;
	esac
done
case "${url}" in
	*ubuntu-24.04.ttis) cp "${FIXTURES}/dry-run-apt.ttis" "${output}" ;;
	https://api.github.com/*)
		printf 'HTTP/2 200\r\nx-ratelimit-remaining: 100\r\n\r\n%s\n' '{"tag_name":"v9.9.9"}'
		;;
	*) printf 'curl %q\n' "$*" >> "${FORBIDDEN_LOG}"; exit 97 ;;
esac
EOF
chmod +x "${stub_bin}/curl"
prepare_dir="${tmp_root}/prepared"
output=$(FIXTURES="${FIXTURES}" run_installer "" --dry-run --versions release --prepare-offline-bundle "${prepare_dir}")
assert_output "${output}" "==== DRY-RUN: Installation Preview ===="
assert_output "${output}" "Firmware: download-only 1.2.3"
assert_output "${output}" "Offline bundle: prepare (${prepare_dir})"$'\n'
assert_no_forbidden
[[ ! -e "${prepare_dir}" ]]

# With --update-firmware off the bundle is still prepared (download-only).
output=$(FIXTURES="${FIXTURES}" run_installer "" --dry-run --versions rolling --update-firmware off \
	--prepare-offline-bundle "${prepare_dir}")
assert_output "${output}" "Firmware: download-only 9.9.9"
assert_no_forbidden
[[ ! -e "${prepare_dir}" ]]

echo -e "\033[0;32mTests passed!\033[0m"
