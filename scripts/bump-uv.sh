#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 Tenstorrent AI ULC
# SPDX-License-Identifier: Apache-2.0
#
# bump-uv.sh — update the pinned uv version and installer hash in install.m4.
#
# The committed UV_INSTALLER_SHA256 is the trust anchor for every user's uv
# install (Astral publishes no checksum for uv-installer.sh itself), so this
# script establishes it carefully:
#   1. Resolve the target uv release (latest by default)
#   2. Refuse releases that are not immutable on GitHub — pre-immutability
#      release assets can be silently replaced upstream
#   3. Download the installer from GitHub and hash it
#   4. Cross-check against the second origin (astral.sh): two independent
#      origins serving identical bytes is the anchor-establishment evidence.
#      Unreachable astral.sh is a warning (some networks block it); a hash
#      MISMATCH between origins is always a hard error.
#   5. Rewrite UV_VERSION and UV_INSTALLER_SHA256 in install.m4
#
# Requirements: curl, jq, sha256sum.
# Usage: scripts/bump-uv.sh [version]   (e.g. 0.12.5; default: latest)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="${1:-}"
if [[ -z "${VERSION}" ]]; then
	VERSION="$(curl -fsSL https://api.github.com/repos/astral-sh/uv/releases/latest | jq -r '.tag_name')"
	echo "[INFO] Latest uv release: ${VERSION}"
fi

release_json="$(curl -fsSL "https://api.github.com/repos/astral-sh/uv/releases/tags/${VERSION}")" \
	|| { echo "[ERROR] No uv release tagged '${VERSION}'" >&2; exit 1; }
immutable="$(jq -r '.immutable // false' <<< "${release_json}")"
if [[ "${immutable}" != "true" ]]; then
	echo "[ERROR] uv release ${VERSION} is not immutable on GitHub; its assets" >&2
	echo "[ERROR] can be silently replaced upstream. Pin a newer, immutable release." >&2
	exit 1
fi
echo "[INFO] Release ${VERSION} is immutable"

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

curl -fsSL -o "${workdir}/gh.sh" \
	"https://github.com/astral-sh/uv/releases/download/${VERSION}/uv-installer.sh"
gh_sum="$(sha256sum "${workdir}/gh.sh" | cut -d' ' -f1)"
echo "[INFO] GitHub    uv-installer.sh: ${gh_sum}"

if curl -fsSL -o "${workdir}/astral.sh" "https://astral.sh/uv/${VERSION}/install.sh"; then
	astral_sum="$(sha256sum "${workdir}/astral.sh" | cut -d' ' -f1)"
	echo "[INFO] astral.sh install.sh:    ${astral_sum}"
	if [[ "${astral_sum}" != "${gh_sum}" ]]; then
		echo "[ERROR] The two origins serve DIFFERENT installer scripts for ${VERSION}." >&2
		echo "[ERROR] Do not pin either hash until this is understood." >&2
		exit 1
	fi
	echo "[INFO] Cross-check passed: both origins agree"
else
	echo "[WARN] astral.sh unreachable from this network; skipping cross-check." >&2
	echo "[WARN] Consider re-running from a network that can reach it." >&2
fi

sed -i \
	-e "s|^readonly UV_VERSION=.*|readonly UV_VERSION=\"${VERSION}\"|" \
	-e "s|^readonly UV_INSTALLER_SHA256=.*|readonly UV_INSTALLER_SHA256=\"${gh_sum}\"|" \
	install.m4

echo "[INFO] install.m4 updated:"
grep -n '^readonly UV_VERSION=\|^readonly UV_INSTALLER_SHA256=' install.m4
echo "[INFO] Review the diff, then commit. CI exercises the pinned install via --use-uv."
