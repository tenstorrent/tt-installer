#!/usr/bin/env bash
# Host unit test for issue #137: "Installer fails if newer firmware was
# installed with apt upgrade".
#
# Regression-guards the fix from PR #138 (commit 3073af4, "Allow downgrades
# when pinned versions are older than installed"): apt_get() must pass
# --allow-downgrades to `apt-get install`, otherwise apt refuses a pinned
# version older than the installed one when -y is used:
#   E: Packages were downgraded and -y was used without --allow-downgrades.
#
# Fully self-contained and non-destructive: apt-get/sudo are mocked on a
# sandboxed PATH; "installed" versions come from a fake dpkg admindir read via
# the real dpkg-query; the fake state mirrors #137 (installed sfpi=7.67.0,
# tenstorrent-dkms=2.9.1 newer than the installer pins 7.61.0/2.9.0). No
# network, no root, no real package state is touched.
#
# Run from anywhere:  bash tests/test-apt-downgrades.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "${SB}"' EXIT
export TEST_FAKE_DPKG="${SB}/fake-dpkg"
mkdir -p "${SB}/bin" "${TEST_FAKE_DPKG}" "${SB}/work"

fails=0
ok()   { echo "ok     - $1"; }
bad()  { echo "NOT OK - $1"; fails=$((fails + 1)); }

# Fake dpkg status: both pinned packages are newer than the installer pins.
add_pkg() { # name version
	printf 'Package: %s\nStatus: install ok installed\nArchitecture: amd64\nVersion: %s\nMaintainer: test <test@example.invalid>\nDescription: fake installed entry\n\n' "$1" "$2" >> "${TEST_FAKE_DPKG}/status"
}
add_pkg sfpi 7.67.0
add_pkg tenstorrent-dkms 2.9.1
add_pkg tenstorrent-tools 1.4.1

cat > "${SB}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
# mock sudo: apply env assignments, then exec verbatim (no privilege used)
while [[ "${1:-}" == *=* && "${1:-}" != -* ]]; do export "${1}"; shift; done
exec "$@"
EOF

cat > "${SB}/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
# mock apt-get implementing apt's downgrade rule: pkg=V with V < installed is
# a DOWNGRADE; with -y and without --allow-downgrades, exit 100 with the exact
# error from issue #137. Version order via the real dpkg --compare-versions;
# installed versions via the real dpkg-query on the fake admindir.
real_dpkg=/usr/bin/dpkg
real_q=/usr/bin/dpkg-query
printf '%s\n' "$@" > "${TEST_FAKE_DPKG}/argv.log"
subcmd=""; args=(); prev=""
for a in "$@"; do
	if [[ "${prev}" == "-o" ]]; then prev=""; continue; fi
	prev="${a}"
	if [[ -z "${subcmd}" && "${a}" != -* ]]; then subcmd="${a}"; continue; fi
	[[ "${a}" == "-o" ]] && continue
	args+=("${a}")
done
if [[ "${subcmd}" == "update" ]]; then
	echo "Reading package lists... Done"
	exit 0
fi
[[ "${subcmd}" == "install" ]] || { echo "E: mock apt-get: unsupported subcommand '${subcmd}'" >&2; exit 100; }
allow=0; have_y=0; specs=()
for a in "${args[@]}"; do
	case "${a}" in
		--allow-downgrades) allow=1 ;;
		-y) have_y=1 ;;
		-*) ;;
		*) specs+=("${a}") ;;
	esac
done
down=0
for spec in "${specs[@]}"; do
	name="${spec%%=*}"; want="${spec#*=}"
	[[ "${want}" == "${spec}" ]] && continue
	inst="$("${real_q}" --admindir="${TEST_FAKE_DPKG}" -W -f='${Version}' "${name}" 2>/dev/null || true)"
	if [[ -n "${inst}" && "$("${real_dpkg}" --compare-versions "${want}" lt "${inst}" && echo yes || echo no)" == "yes" ]]; then
		down=$((down + 1))
	fi
done
echo "0 upgraded, 0 newly installed, ${down} downgraded, 0 to remove and 0 not upgraded."
if [[ "${down}" -gt 0 && "${have_y}" -eq 1 && "${allow}" -eq 0 ]]; then
	echo "E: Packages were downgraded and -y was used without --allow-downgrades."
	exit 100
fi
exit 0
EOF
chmod +x "${SB}/bin/sudo" "${SB}/bin/apt-get"

# Load apt_get() verbatim from the tracked source (no argbash needed).
fn="${SB}/apt_get.fn"
awk '/^apt_get\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "${REPO_ROOT}/install.m4" > "${fn}"
grep -q 'apt-get' "${fn}" || { echo "BAIL OUT - could not extract apt_get() from install.m4"; exit 99; }

# Minimal environment matching install.sh's shell semantics.
WORKDIR="${SB}/work"
APT_LOCK_TIMEOUT=120
error() { echo "[error] $*" >&2; }
warn() { echo "[warn] $*" >&2; }
set -o pipefail
# shellcheck source=/dev/null
source "${fn}"

# 1. The #137 scenario: pins older than installed must succeed.
PATH="${SB}/bin:${PATH}" apt_get install -y sfpi=7.61.0 tenstorrent-dkms=2.9.0 tenstorrent-tools=1.4.1 >/dev/null 2>&1
rc=$?
argv="$(tr '\n' ' ' < "${TEST_FAKE_DPKG}/argv.log")"
[[ ${rc} -eq 0 ]] && ok "pinned-older install succeeds (rc=0)" || bad "pinned-older install rc=${rc}"
[[ "${argv}" == *"--allow-downgrades"* ]] && ok "install passes --allow-downgrades" || bad "install argv missing --allow-downgrades: ${argv}"

# 2. Only install gets the flag.
PATH="${SB}/bin:${PATH}" apt_get update >/dev/null 2>&1
rc=$?
argv="$(tr '\n' ' ' < "${TEST_FAKE_DPKG}/argv.log")"
[[ ${rc} -eq 0 && "${argv}" != *"--allow-downgrades"* ]] && ok "update succeeds and does not pass --allow-downgrades" || bad "update rc=${rc} argv=${argv}"

# 3. The mock reproduces #137 when the flag is absent (sanity of the harness).
PATH="${SB}/bin:${PATH}" "${SB}/bin/apt-get" install -y sfpi=7.61.0 >/dev/null 2>&1
[[ $? -eq 100 ]] && ok "without --allow-downgrades apt refuses the downgrade (rc=100, the #137 error)" || bad "mock did not reproduce the #137 refusal"

if [[ ${fails} -eq 0 ]]; then
	echo "I137_UNIT: PASS - apt_get() downgrade handling guards issue #137"
	exit 0
fi
echo "I137_UNIT: FAIL - ${fails} check(s) failed"
exit 1
