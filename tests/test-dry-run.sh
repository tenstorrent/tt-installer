#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="${ROOT_DIR}/install.sh"
FIXTURE="${ROOT_DIR}/tests/fixtures/dry-run.ttis"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "${TEST_TMP}"' EXIT

if [[ ! -x "${INSTALLER}" && ! -f "${INSTALLER}" ]]; then
	echo "install.sh is missing; generate it before running this test" >&2
	exit 1
fi
command -v jq >/dev/null || { echo "jq is required for dry-run tests" >&2; exit 1; }

STUB_BIN="${TEST_TMP}/bin"
mkdir -p "${STUB_BIN}"
FORBIDDEN_LOG="${TEST_TMP}/forbidden.log"
touch "${FORBIDDEN_LOG}"
export FORBIDDEN_LOG FIXTURE

make_forbidden_stub() {
	local command_name=$1
	cat > "${STUB_BIN}/${command_name}" <<'EOF'
#!/bin/bash
echo "$(basename "$0") $*" >> "${FORBIDDEN_LOG}"
exit 97
EOF
	chmod +x "${STUB_BIN}/${command_name}"
}

for command_name in sudo apt apt-get dnf dkms tt-flash reboot uv pip pip3 pipx systemctl usermod git; do
	make_forbidden_stub "${command_name}"
done

# Runtime inspection is allowed, but pulling or running an image is not.
cat > "${STUB_BIN}/docker" <<'EOF'
#!/bin/bash
case "${1:-}" in
	--version) echo "Docker version 27.0.0" ;;
	info) echo "mock Docker daemon" ;;
	*) echo "docker $*" >> "${FORBIDDEN_LOG}"; exit 97 ;;
esac
EOF
chmod +x "${STUB_BIN}/docker"

cat > "${STUB_BIN}/podman" <<'EOF'
#!/bin/bash
echo "podman $*" >> "${FORBIDDEN_LOG}"
exit 97
EOF
chmod +x "${STUB_BIN}/podman"

# The release channel fetches its golden .ttis file. Serve the fixture without
# touching the network; any unexpected curl shape fails the test.
cat > "${STUB_BIN}/curl" <<'EOF'
#!/bin/bash
destination=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		-o) destination="${2:?missing curl output path}"; shift 2 ;;
		*) shift ;;
	esac
done
if [[ -z "${destination}" ]]; then
	echo "unexpected curl invocation" >&2
	exit 97
fi
cp "${FIXTURE}" "${destination}"
EOF
chmod +x "${STUB_BIN}/curl"

export PATH="${STUB_BIN}:${PATH}"

assert_plan() {
	local output=$1
	grep -q "TENSTORRENT INSTALLATION PLAN" "${output}"
	grep -q "Distribution:" "${output}"
	grep -q "Architecture:" "${output}"
	grep -q "Kernel:" "${output}"
	grep -q "Base system packages" "${output}"
	grep -q "Tenstorrent system packages" "${output}"
	grep -q "Python packages" "${output}"
	grep -q "HugePages:" "${output}"
	grep -q "Container runtime:" "${output}"
	grep -q "Container images:" "${output}"
	grep -q "Firmware:" "${output}"
	grep -q "PREVIEW ONLY" "${output}"
}

run_success_case() {
	local name=$1
	shift
	local case_home="${TEST_TMP}/home-${name}"
	local output="${TEST_TMP}/${name}.out"
	local export_path="${case_home}/state-export.ttis"
	mkdir -p "${case_home}"
	: > "${FORBIDDEN_LOG}"

	HOME="${case_home}" bash "${INSTALLER}" \
		--dry-run \
		--mode-non-interactive \
		--update-firmware=off \
		--no-install-inference-server \
		--no-install-studio \
		--export-schema="${export_path}" \
		--reboot-option=always \
		"$@" > "${output}" 2>&1

	assert_plan "${output}"
	[[ ! -e "${export_path}" ]] || { echo "${name}: dry-run exported a schema" >&2; exit 1; }
	[[ ! -s "${FORBIDDEN_LOG}" ]] || { echo "${name}: forbidden command invoked:" >&2; cat "${FORBIDDEN_LOG}" >&2; exit 1; }
	if find "${case_home}" -mindepth 1 -print -quit | grep -q .; then
		echo "${name}: installer wrote inside HOME" >&2
		find "${case_home}" -mindepth 1 -print >&2
		exit 1
	fi
	echo "PASS: ${name}"
}

run_success_case release --versions=release
grep -q "tenstorrent-dkms=1.2.3" "${TEST_TMP}/release.out"
grep -q "tt-smi==4.5.6" "${TEST_TMP}/release.out"
run_success_case rolling --versions=rolling --fw-version=18.9.0
run_success_case imported --versions="${FIXTURE}"
grep -q "tenstorrent-tools=2.3.4" "${TEST_TMP}/imported.out"
run_success_case container --versions=rolling --mode-container --fw-version=18.9.0
grep -q "Disabled — no HugePages configuration will be written" "${TEST_TMP}/container.out"
grep -q "Selected: none" "${TEST_TMP}/container.out"
if grep -q -- "- tenstorrent-dkms" "${TEST_TMP}/container.out"; then
	echo "container mode unexpectedly planned a KMD package" >&2
	exit 1
fi

INVALID_TTIS="${TEST_TMP}/invalid.ttis"
echo '{not valid json' > "${INVALID_TTIS}"
if HOME="${TEST_TMP}/invalid-home" bash "${INSTALLER}" --dry-run --versions="${INVALID_TTIS}" > "${TEST_TMP}/invalid-ttis.out" 2>&1; then
	echo "invalid .ttis unexpectedly succeeded" >&2
	exit 1
fi
grep -q "not valid JSON" "${TEST_TMP}/invalid-ttis.out"
echo "PASS: invalid .ttis fails"

if bash "${INSTALLER}" --dry-run --install-container-runtime=invalid > "${TEST_TMP}/invalid-arg.out" 2>&1; then
	echo "invalid option value unexpectedly succeeded" >&2
	exit 1
fi
grep -q "Invalid container runtime option" "${TEST_TMP}/invalid-arg.out"
echo "PASS: invalid option value fails"

if bash "${INSTALLER}" --dry-run --definitely-not-an-option > "${TEST_TMP}/unknown-arg.out" 2>&1; then
	echo "unknown argument unexpectedly succeeded" >&2
	exit 1
fi
echo "PASS: unknown argument fails"

echo "All dry-run tests passed"
