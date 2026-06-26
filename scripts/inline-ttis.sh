#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 Tenstorrent AI ULC
# SPDX-License-Identifier: Apache-2.0
#
# inline-ttis.sh — concatenate ttis.sh into the generated install.sh.
#
# The released install.sh must be a single self-contained file so it can run via
#   /bin/bash -c "$(curl -fsSL .../install.sh)"
# with no second file to download. This script replaces the `# __TTIS_INLINE__`
# placeholder line (emitted from install.m4) with the body of ttis.sh between its
# `# >>> TTIS_INLINE_BEGIN <<<` / `# >>> TTIS_INLINE_END <<<` markers.
#
# Usage: scripts/inline-ttis.sh <install.sh> <ttis.sh>
set -euo pipefail

INSTALL_SH="${1:?Usage: inline-ttis.sh <install.sh> <ttis.sh>}"
TTIS_SH="${2:?Usage: inline-ttis.sh <install.sh> <ttis.sh>}"

readonly BEGIN_MARK='# >>> TTIS_INLINE_BEGIN <<<'
readonly END_MARK='# >>> TTIS_INLINE_END <<<'
readonly PLACEHOLDER='# __TTIS_INLINE__'

for f in "${INSTALL_SH}" "${TTIS_SH}"; do
	[[ -f "${f}" ]] || { echo "[ERROR] No such file: ${f}" >&2; exit 1; }
done

if ! grep -qxF "${PLACEHOLDER}" "${INSTALL_SH}"; then
	echo "[ERROR] Placeholder '${PLACEHOLDER}' not found in ${INSTALL_SH}" >&2
	exit 1
fi

# Extract the inlinable body of ttis.sh (between the markers, exclusive).
body_file="$(mktemp)"
out_file="$(mktemp)"
trap 'rm -f "${body_file}" "${out_file}"' EXIT

awk -v b="${BEGIN_MARK}" -v e="${END_MARK}" '
	$0 == b { inb=1; next }
	$0 == e { inb=0; next }
	inb     { print }
' "${TTIS_SH}" > "${body_file}"

if [[ ! -s "${body_file}" ]]; then
	echo "[ERROR] No content found between TTIS inline markers in ${TTIS_SH}" >&2
	exit 1
fi

# Replace the placeholder line with the extracted body. getline reproduces the
# body verbatim (backslashes, brackets, quotes) with no escaping concerns.
awk -v ph="${PLACEHOLDER}" -v bf="${body_file}" '
	$0 == ph {
		print "# --- begin inlined ttis.sh (build-time, see scripts/inline-ttis.sh) ---"
		while ((getline line < bf) > 0) print line
		close(bf)
		print "# --- end inlined ttis.sh ---"
		next
	}
	{ print }
' "${INSTALL_SH}" > "${out_file}"

cat "${out_file}" > "${INSTALL_SH}"
echo "[INFO] Inlined ttis.sh into ${INSTALL_SH}"
