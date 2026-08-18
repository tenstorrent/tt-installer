#!/usr/bin/env bash
# Host unit test for issue #121: "Add option to run
# tt-update-tensix-disable-count on firmware before install".
#
# Covers the --patch-tensix-disable-count / --tensix-disable-count handling in
# install.m4's firmware block:
#   (a) flag on  -> tool invoked exactly once with the expected argv and the
#                   patched bundle (not the original) is flashed;
#   (b) flag off -> original bundle flashed, tool never invoked;
#   (c) flag on but the tool is not on PATH -> installer error_exits before
#       any flashing.
#
# The patch contract this guards: the tool is NOT idempotent, so install.m4
# must run it exactly once, input -> distinct output file, then mv over the
# bundle. Assertions are on argv and file identity (marker content), never on
# bundle bytes/sizes/hashes (the real tool re-encodes the whole bundle and
# output sizes vary between runs).
#
# Fully self-contained and non-destructive: curl/tt-flash/
# tt-update-tensix-disable-count are mocked on a sandboxed PATH and the
# firmware block is sourced verbatim from install.m4 (no argbash needed).
# No network, no root, no device access.
#
# Run from anywhere:  bash tests/test-i121-tensix-disable-patch.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "${SB}"' EXIT
mkdir -p "${SB}/bin" "${SB}/bin-notool" "${SB}/work"

fails=0
ok()  { echo "ok     - $1"; }
bad() { echo "NOT OK - $1"; fails=$((fails + 1)); }

# --- mocks ---------------------------------------------------------------

cat > "${SB}/bin/curl" <<'EOF'
#!/usr/bin/env bash
# mock curl -O: write a fake bundle named after the URL basename into cwd
for a in "$@"; do
	case "${a}" in
		http*) printf 'original-bundle\n' > "${a##*/}" ;;
	esac
done
exit 0
EOF

cat > "${SB}/bin/tt-flash" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${TTFLASH_ARGV}"
exit 0
EOF

cat > "${SB}/bin/tt-update-tensix-disable-count" <<'EOF'
#!/usr/bin/env bash
# mock patch tool: record argv, then copy --input to --output and append a
# marker (the real tool re-encodes; identity of content is all we assert)
printf '%s\n' "$@" > "${TDC_ARGV}"
in=""; out=""; prev=""
for a in "$@"; do
	case "${prev}" in
		--input) in="${a}" ;;
		--output) out="${a}" ;;
	esac
	prev="${a}"
done
[[ -n "${in}" && -n "${out}" ]] || exit 2
cp "${in}" "${out}" && echo "patched-by-mock" >> "${out}"
EOF

chmod +x "${SB}/bin/"*
cp "${SB}/bin/curl" "${SB}/bin/tt-flash" "${SB}/bin-notool/"

# --- extract the firmware block verbatim from the tracked source ----------

FW_BLOCK="${SB}/fw-block.sh"
sed -n '/^\t# Update firmware using tt-flash$/,/^\tfi$/p' "${REPO_ROOT}/install.m4" > "${FW_BLOCK}"
grep -q 'tt-update-tensix-disable-count --input' "${FW_BLOCK}" || { echo "BAIL OUT - could not extract firmware block (or patch handling missing) from install.m4"; exit 99; }

# Minimal environment matching install.sh's shell semantics.
log()   { echo "[info] $*"; }
warn()  { echo "[warn] $*"; }
error_exit() { echo "[error] $*" >&2; exit 1; }
verify_download() { [[ -f "$1" ]]; }
fetch_latest_version() { echo "0.0.0-mock"; }

# Runs the extracted firmware block in a subshell with mocks on PATH.
# Caller sets: _arg_update_firmware _arg_patch_tensix_disable_count
# _arg_tensix_disable_count WORKDIR TDC_ARGV TTFLASH_ARGV FW_DIR (path with/without the tool)
run_fw_block() { (
	set -o pipefail
	# shellcheck source=/dev/null
	PATH="${FW_DIR}:/usr/bin:/bin"
	cd "${WORKDIR}"
	source "${FW_BLOCK}"
); }

export TDC_ARGV TTFLASH_ARGV # mocks are child processes; they read these

FWV=9.9.9
FW_FILE="fw_pack-${FWV}.fwbundle"

# --- case (a): flag on -> patch exactly once, flash the patched bundle ----

W="${SB}/case-a"; mkdir -p "${W}"
WORKDIR="${W}"
TDC_ARGV="${W}/tdc.argv"; TTFLASH_ARGV="${W}/ttflash.argv"
_arg_update_firmware="force"
_arg_patch_tensix_disable_count="on"
_arg_tensix_disable_count="5" # non-default: proves value passthrough
_arg_fw_version="${FWV}"
FW_DIR="${SB}/bin"
run_fw_block >"${W}/out.log" 2>&1
rc=$?

cat > "${W}/tdc.expected" <<EOF
--input
${FW_FILE}
--output
${FW_FILE}.patched
--board
P150A-1
--board
P150B-1
--board
P150C-1
--disable-count
5
EOF
cat > "${W}/ttflash.expected" <<EOF
flash
${FW_FILE}
--force
EOF

[[ ${rc} -eq 0 ]] && ok "flag on: firmware block succeeds (rc=0)" || bad "flag on: rc=${rc}"
diff -u "${W}/tdc.expected" "${W}/tdc.argv" >/dev/null 2>&1 \
	&& ok "flag on: tool argv exact (input->${FW_FILE}.patched, 3 boards, --disable-count 5, single invocation)" \
	|| bad "flag on: tool argv mismatch: $(tr '\n' ' ' < "${W}/tdc.argv" 2>/dev/null)"
diff -u "${W}/ttflash.expected" "${W}/ttflash.argv" >/dev/null 2>&1 \
	&& ok "flag on: flashed with --force" || bad "flag on: tt-flash argv: $(tr '\n' ' ' < "${W}/ttflash.argv" 2>/dev/null)"
grep -q 'patched-by-mock' "${W}/${FW_FILE}" \
	&& ok "flag on: flashed file IS the patched output (mv replaced the bundle)" \
	|| bad "flag on: flashed bundle was not the patched one"
[[ ! -e "${W}/${FW_FILE}.patched" ]] \
	&& ok "flag on: no .patched leftover" || bad "flag on: ${FW_FILE}.patched still exists"

# --- case (b): flag off -> original flashed, tool never invoked -----------

W="${SB}/case-b"; mkdir -p "${W}"
WORKDIR="${W}"
TDC_ARGV="${W}/tdc.argv"; TTFLASH_ARGV="${W}/ttflash.argv"
_arg_update_firmware="on"
_arg_patch_tensix_disable_count="off"
_arg_tensix_disable_count="0"
_arg_fw_version="${FWV}"
FW_DIR="${SB}/bin" # tool IS available and must still not run
run_fw_block >"${W}/out.log" 2>&1
rc=$?

[[ ${rc} -eq 0 ]] && ok "flag off: firmware block succeeds (rc=0)" || bad "flag off: rc=${rc}"
[[ ! -e "${W}/tdc.argv" ]] \
	&& ok "flag off: tool never invoked" || bad "flag off: tool ran: $(tr '\n' ' ' < "${W}/tdc.argv")"
printf 'flash\n%s\n' "${FW_FILE}" > "${W}/ttflash.expected"
diff -u "${W}/ttflash.expected" "${W}/ttflash.argv" >/dev/null 2>&1 \
	&& ok "flag off: original flashed (no --force)" || bad "flag off: tt-flash argv: $(tr '\n' ' ' < "${W}/ttflash.argv" 2>/dev/null)"
cmp -s <(printf 'original-bundle\n') "${W}/${FW_FILE}" \
	&& ok "flag off: flashed bundle is the untouched original" || bad "flag off: flashed bundle was modified"

# --- case (c): flag on, tool missing -> error_exit, no flash --------------

W="${SB}/case-c"; mkdir -p "${W}"
WORKDIR="${W}"
TDC_ARGV="${W}/tdc.argv"; TTFLASH_ARGV="${W}/ttflash.argv"
_arg_update_firmware="force"
_arg_patch_tensix_disable_count="on"
_arg_tensix_disable_count="0"
_arg_fw_version="${FWV}"
FW_DIR="${SB}/bin-notool" # no tt-update-tensix-disable-count here
run_fw_block >"${W}/out.log" 2>&1
rc=$?

[[ ${rc} -ne 0 ]] && ok "tool missing: installer fails (rc=${rc})" || bad "tool missing: rc=0, expected failure"
grep -q 'tt-update-tensix-disable-count is not installed or not in PATH' "${W}/out.log" \
	&& ok "tool missing: error names the tool and the pip install hint" || bad "tool missing: unexpected error output"
[[ ! -e "${W}/ttflash.argv" ]] \
	&& ok "tool missing: nothing was flashed" || bad "tool missing: tt-flash ran anyway"

if [[ ${fails} -eq 0 ]]; then
	echo "I121_UNIT: PASS - firmware-block patch handling guards issue #121 (argv + patched-file identity, all 3 cases)"
	exit 0
fi
echo "I121_UNIT: FAIL - ${fails} check(s) failed"
exit 1
