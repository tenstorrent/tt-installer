#!/usr/bin/env bash
# Smoke test for --dry-run mode. Runs the built install.sh in dry-run mode and
# asserts that the printed plan contains the platform details and selected
# packages required by issue #140, without making any system changes.
#
# Usage: tests/test-dry-run.sh [path-to-install.sh]   (default: ./install.sh)

set -euo pipefail

INSTALL_SH="${1:-./install.sh}"

if [[ ! -f "${INSTALL_SH}" ]]; then
    echo "ERROR: ${INSTALL_SH} not found. Build it first (make install.sh)." >&2
    exit 2
fi

OUT="$(mktemp)"
trap 'rm -f "${OUT}"' EXIT

# --dry-run must print the plan and exit 0 without modifying the system.
bash "${INSTALL_SH}" --dry-run > "${OUT}" 2>&1
rc=$?
if [[ ${rc} -ne 0 ]]; then
    echo "ERROR: --dry-run exited with status ${rc}" >&2
    cat "${OUT}" >&2
    exit 1
fi

fail() {
    echo "ERROR: missing expected output: $1" >&2
    cat "${OUT}" >&2
    exit 1
}

grep -q "Distribution:" "${OUT}" || fail "Distribution line"
grep -q "Architecture:" "${OUT}" || fail "Architecture line"
grep -q "Kernel:" "${OUT}" || fail "Kernel line"
grep -q "System packages:" "${OUT}" || fail "System packages section"
grep -q "Python packages:" "${OUT}" || fail "Python packages section"
grep -q "Kernel-Mode Driver:" "${OUT}" || fail "Kernel-Mode Driver line"
grep -q "Container runtime:" "${OUT}" || fail "Container runtime line"
grep -q "Firmware update:" "${OUT}" || fail "Firmware update line"

echo "OK: --dry-run smoke test passed"
