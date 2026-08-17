#!/usr/bin/env bash
# Tests for rustup availability detection (issue #111).
#
# rustup is packaged from Debian 13 (trixie) and Ubuntu 24.04 (noble) onwards,
# and not at all before that, so the installer has to branch on the suite
# version rather than the distro alone. This exercises that branch without
# needing a container per suite.
#
# The functions are extracted from install.m4 rather than copied, so the test
# fails if the implementation moves or changes shape.
#
# Usage: tests/test-rustup-detection.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="${SCRIPT_DIR}/../install.m4"

if [[ ! -f "${SOURCE_FILE}" ]]; then
	echo "cannot find install.m4 at ${SOURCE_FILE}" >&2
	exit 1
fi

# Pull the two functions under test out of install.m4 and into this shell.
extract_function() {
	awk -v name="$1" '
		$0 ~ "^" name "\\(\\) \\{" { collecting = 1 }
		collecting { print }
		collecting && /^\}$/ { exit }
	' "${SOURCE_FILE}"
}

for fn in version_ge has_packaged_rustup; do
	body="$(extract_function "${fn}")"
	if [[ -z "${body}" ]]; then
		echo "FAIL: could not extract ${fn}() from install.m4" >&2
		exit 1
	fi
	eval "${body}"
done

PASS=0
FAIL=0

check() {
	local desc="$1" expected="$2" actual="$3"
	if [[ "${expected}" == "${actual}" ]]; then
		PASS=$((PASS + 1))
	else
		FAIL=$((FAIL + 1))
		echo "FAIL: ${desc} — expected ${expected}, got ${actual}"
	fi
}

# ---- version_ge ----------------------------------------------------------
version_case() {
	local a="$1" b="$2" expected="$3"
	local actual="no"
	version_ge "${a}" "${b}" && actual="yes"
	check "version_ge '${a}' '${b}'" "${expected}" "${actual}"
}

version_case "13"    "13"    yes   # equal
version_case "14"    "13"    yes
version_case "12"    "13"    no
version_case "9"     "13"    no    # lexical compare would get this wrong
version_case "24.04" "24.04" yes
version_case "24.10" "24.04" yes   # lexical compare would get this wrong
version_case "22.04" "24.04" no
version_case "25.04" "24.04" yes
version_case "100"   "99"    yes   # lexical compare would get this wrong
version_case ""      "13"    no    # missing VERSION_ID must not pass

# ---- has_packaged_rustup -------------------------------------------------
rustup_case() {
	local distro="$1" version="$2" expected="$3"
	local actual="no"
	DISTRO_ID="${distro}" VERSION_ID="${version}"
	has_packaged_rustup && actual="yes"
	check "has_packaged_rustup ${distro} ${version:-<unset>}" "${expected}" "${actual}"
}

# Verified against the package archives:
#   packages.debian.org/trixie/rustup   1.27.1-3   present
#   packages.debian.org/bookworm/rustup            absent
#   packages.ubuntu.com/noble/rustup    1.26.0     present (universe)
#   packages.ubuntu.com/jammy/rustup               absent
rustup_case debian 13      yes
rustup_case debian 12      no
rustup_case debian 11      no
rustup_case debian 14      yes
rustup_case debian ""      no    # testing/unstable carry no VERSION_ID
rustup_case ubuntu 24.04   yes
rustup_case ubuntu 22.04   no
rustup_case ubuntu 20.04   no
rustup_case ubuntu 24.10   yes
rustup_case ubuntu 26.04   yes
rustup_case ubuntu ""      no
rustup_case fedora 42      no    # not apt-based; falls to the dnf branch
rustup_case rhel   9       no

echo
echo "${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]]
