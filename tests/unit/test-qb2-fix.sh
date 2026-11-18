#!/usr/bin/env bash
# Unit tests for the QuietBox 2 preinstaller ISO <= v1.2.0 repairs: the gate,
# the two "is it needed" tests, and both rewrites, on a temporary tree.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
INSTALLER="${ROOT}/install.sh"
[[ -f "${INSTALLER}" ]] || { echo "install.sh is missing" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT

export INSTALLER_SOURCE_ONLY=1
export TT_QB2_FIX_ROOT="${tmp}/root"
export XDG_CONFIG_HOME="${tmp}/config"
# shellcheck disable=SC1090
source "${INSTALLER}"

expect_fail() {
	echo "expected failure: $1"
	shift
	if "$@"; then
		echo "did not fail as expected: $*" >&2
		exit 1
	fi
}

unit="${TT_QB2_FIX_ROOT}/etc/systemd/user/tt-hello-world.service"
conf="${TT_QB2_FIX_ROOT}/etc/update-manager/release-upgrades"
cfg="${XDG_CONFIG_HOME}/systemd/user"
link="${cfg}/default.target.wants/tt-hello-world.service"
mask="${cfg}/tt-hello-world.service"

# The detection must never depend on who runs the tests; stub id. The apply
# step must never reach a real user manager; stub systemctl to fail, as it
# does without a user bus, so the file-only fallback is what runs.
fake_uid=1000
id() {
	case "${1:-}" in
		-u) echo "${fake_uid}" ;;
		*) echo ttuser ;;
	esac
}
systemctl() { return 1; }

# Unit file as shipped by ISOs up to v1.2.0 (legacy) or v1.2.1 (fixed).
write_unit() {
	mkdir -p "$(dirname "${unit}")"
	{
		echo "[Unit]"
		echo "Description=Tenstorrent hello world video"
		[[ "$1" = legacy ]] && echo "Wants=graphical-session.target"
		echo "After=graphical-session.target"
		echo
		echo "[Service]"
		echo "ExecStart=${2:-/usr/local/bin/tt-hello-world.sh}"
		echo
		echo "[Install]"
		echo "WantedBy=graphical-session.target"
	} > "${unit}"
}

write_conf() {
	mkdir -p "$(dirname "${conf}")"
	printf '%s\n' "# Default behavior for the release upgrader." "" "[DEFAULT]" "$@" > "${conf}"
}

reset_user() {
	rm -rf "${XDG_CONFIG_HOME}"
	mkdir -p "${cfg}/default.target.wants"
	ln -s "${1:-/etc/systemd/user/tt-hello-world.service}" "${link}"
}

# --- gate ---
expect_fail "gate: no unit file" qb2_legacy_iso_install
write_unit fixed
expect_fail "gate: v1.2.1 unit without Wants=" qb2_legacy_iso_install
write_unit legacy /usr/bin/something-else
expect_fail "gate: different ExecStart" qb2_legacy_iso_install
write_unit legacy
mv "${unit}" "${unit}.real"
ln -s "${unit}.real" "${unit}"
expect_fail "gate: unit is a symlink" qb2_legacy_iso_install
rm "${unit}"
mv "${unit}.real" "${unit}"
qb2_legacy_iso_install

# --- action A: detection ---
reset_user
qb2_hello_world_fix_needed
fake_uid=0
expect_fail "A: running as root" qb2_hello_world_fix_needed
fake_uid=1000
rm "${link}"
expect_fail "A: link missing" qb2_hello_world_fix_needed
reset_user /usr/lib/systemd/user/other.service
expect_fail "A: link points elsewhere" qb2_hello_world_fix_needed
reset_user
ln -s /dev/null "${mask}"
expect_fail "A: already masked" qb2_hello_world_fix_needed
reset_user
write_unit fixed
expect_fail "A: gate fails" qb2_hello_world_fix_needed
write_unit legacy

# --- action A: apply through the file-only fallback, then a no-op re-run ---
reset_user
touch "${cfg}/default.target.wants/unrelated.service"
out=$(apply_qb2_hello_world_fix)
[[ "${out}" == *"The welcome video is now off"* ]]
[[ ! -e "${link}" && ! -L "${link}" ]]
[[ "$(readlink "${mask}")" = /dev/null ]]
[[ -f "${cfg}/default.target.wants/unrelated.service" ]]
expect_fail "A: not needed after apply" qb2_hello_world_fix_needed
[[ -z "$(apply_qb2_hello_world_fix)" ]]

# A unit file the user put at the mask path is left alone.
reset_user
echo "[Service]" > "${mask}"
qb2_hello_world_fix_files
[[ ! -L "${link}" && -f "${mask}" && ! -L "${mask}" ]]
expect_fail "A: not needed once the link is gone" qb2_hello_world_fix_needed

# Outside the gate, apply changes nothing.
write_unit fixed
reset_user
[[ -z "$(apply_qb2_hello_world_fix)" ]]
[[ -L "${link}" && ! -e "${mask}" ]]
write_unit legacy

# --- action B: detection ---
write_conf "Prompt=lts"
qb2_upgrade_prompt_fix_needed
write_conf "Prompt=normal"
qb2_upgrade_prompt_fix_needed
write_conf "Prompt=never"
expect_fail "B: already never" qb2_upgrade_prompt_fix_needed
rm "${conf}"
qb2_upgrade_prompt_fix_needed
write_conf
qb2_upgrade_prompt_fix_needed
write_unit fixed
write_conf "Prompt=lts"
expect_fail "B: gate fails" qb2_upgrade_prompt_fix_needed
write_unit legacy

# --- action B: rewrite (no command prefix here; sudo on a real system) ---
write_conf "Prompt=lts"
qb2_write_upgrade_prompt "${conf}"
[[ "$(cat "${conf}")" = "$(printf '%s\n' "# Default behavior for the release upgrader." "" "[DEFAULT]" "Prompt=never")" ]]
expect_fail "B: not needed after rewrite" qb2_upgrade_prompt_fix_needed

write_conf
qb2_write_upgrade_prompt "${conf}"
[[ "$(cat "${conf}")" = "$(printf '%s\n' "[DEFAULT]" "Prompt=never")" ]]

rm -rf "$(dirname "${conf}")"
qb2_write_upgrade_prompt "${conf}"
[[ "$(cat "${conf}")" = "$(printf '%s\n' "[DEFAULT]" "Prompt=never")" ]]

# The command prefix is what runs each step.
write_conf "Prompt=lts"
qb2_write_upgrade_prompt "${conf}" env
grep -qx 'Prompt=never' "${conf}"

# --- apply B end to end, with sudo stubbed to run the command directly ---
# shellcheck disable=SC2329  # the sudo stubs are called by the sourced installer
sudo() { "$@"; }
write_conf "Prompt=lts"
out=$(apply_qb2_upgrade_prompt_fix)
[[ "${out}" == *"Prompt=never"*"each time it runs"* ]]
grep -qx 'Prompt=never' "${conf}"
[[ -z "$(apply_qb2_upgrade_prompt_fix)" ]]

# A failing sudo warns and does not abort.
# shellcheck disable=SC2329
sudo() { return 1; }
write_conf "Prompt=lts"
out=$(apply_qb2_upgrade_prompt_fix)
[[ "${out}" == *"Could not turn off release-upgrade prompts"* ]]
grep -qx 'Prompt=lts' "${conf}"

# Outside the gate, the file is never touched.
sudo() { echo "sudo must not be called" >&2; exit 1; }
write_unit fixed
[[ -z "$(apply_qb2_upgrade_prompt_fix)" ]]
grep -qx 'Prompt=lts' "${conf}"
rm "${unit}"
[[ -z "$(apply_qb2_upgrade_prompt_fix)" ]]
grep -qx 'Prompt=lts' "${conf}"

# --- dry-run plan names the repairs only when they would apply ---
write_unit legacy
reset_user
plan=$(render_qb2_fix_plan)
[[ "${plan}" == *"QuietBox 2 ISO repair: suppressed (disable and mask tt-hello-world.service)"* ]]
[[ "${plan}" == *"QuietBox 2 ISO repair: suppressed (set Prompt=never in /etc/update-manager/release-upgrades)"* ]]
[[ -L "${link}" ]]
grep -qx 'Prompt=lts' "${conf}"
write_unit fixed
[[ -z "$(render_qb2_fix_plan)" ]]

echo -e "\033[0;32mTests passed!\033[0m"
