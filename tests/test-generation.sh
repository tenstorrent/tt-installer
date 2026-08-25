#!/usr/bin/env bash
# Validates the generated install.sh produced by the build pipeline
# (argbash + scripts/inline-ttis.sh): syntax, inlined ttis body, parser
# flags, planning functions and the source-only guard.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="${ROOT}/install.sh"
TTIS="${ROOT}/ttis.sh"
TMPDIR_TESTS="${TMPDIR:-/tmp}"
tmp_root=$(mktemp -d "${TMPDIR_TESTS}/tt-generation-XXXXXX")
trap 'rm -rf "${tmp_root}"' EXIT

[[ -f "${INSTALLER}" ]] || { echo "generation check: install.sh is missing (run 'make install.sh' first)" >&2; exit 1; }
[[ -f "${TTIS}" ]] || { echo "generation check: ttis.sh is missing" >&2; exit 1; }

fail() { echo "generation check failed: $1" >&2; exit 1; }

bash -n "${INSTALLER}" || fail "syntax check"

grep -qF '__TTIS_INLINE__' "${INSTALLER}" && fail "ttis placeholder still present"
grep -qF 'TTIS_PACKAGE_MAP' "${INSTALLER}" || fail "TTIS_PACKAGE_MAP not inlined"
grep -qF '# --- begin inlined ttis.sh' "${INSTALLER}" || fail "inlined ttis begin marker missing"
grep -qF '# --- end inlined ttis.sh' "${INSTALLER}" || fail "inlined ttis end marker missing"
grep -qF -- '--dry-run' "${INSTALLER}" || fail "dry-run flag missing"
grep -q '_arg_dry_run' "${INSTALLER}" || fail "_arg_dry_run parser variable missing"
grep -qF 'main "$@"' "${INSTALLER}" || fail "main invocation missing"
grep -q 'INSTALLER_SOURCE_ONLY' "${INSTALLER}" || fail "source-only guard missing"
for fn in normalize_options resolve_base_packages build_package_registry \
		resolve_package_actions disable_unused_container_runtime \
		resolve_container_runtime resolve_firmware_action \
		render_install_plan; do
	grep -qE "^${fn}\(\)" "${INSTALLER}" || fail "planning function ${fn} missing"
done

# Inlining round-trip: the body inlined into install.sh must match the
# TTIS_INLINE_BEGIN/END section of ttis.sh, modulo CRLF normalization.
tr -d '\r' < "${TTIS}" | awk '
	$0 == "# >>> TTIS_INLINE_BEGIN <<<" { inb=1; next }
	$0 == "# >>> TTIS_INLINE_END <<<"   { inb=0; next }
	inb { print }
' > "${tmp_root}/expected.body"
awk '
	$0 ~ /^# --- begin inlined ttis.sh/ { inb=1; next }
	$0 ~ /^# --- end inlined ttis.sh/   { inb=0; next }
	inb { print }
' "${INSTALLER}" | tr -d '\r' > "${tmp_root}/actual.body"

diff -u "${tmp_root}/expected.body" "${tmp_root}/actual.body" \
	|| fail "inlined ttis body differs from ttis.sh"

echo -e "\033[0;32mTests passed!\033[0m"
