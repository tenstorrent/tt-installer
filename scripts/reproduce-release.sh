#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 Tenstorrent AI ULC
# SPDX-License-Identifier: Apache-2.0
#
# reproduce-release.sh — independently verify a release by rebuilding it.
#
# Clones the tagged source, rebuilds install.sh with the exact build recorded
# at that tag (scripts/build-install-sh.sh, argbash pinned by digest), and
# byte-compares the result against the published release assets. A match
# proves the assets were built from the tagged source — with no trust in
# GitHub's release storage or attestation infrastructure required.
#
# Complements (not replaces) attestation verification:
#   gh attestation verify install.sh --repo tenstorrent/tt-installer
#
# Requirements: git, curl, docker, sha256sum.
# Only tags that contain scripts/build-install-sh.sh are reproducible;
# earlier releases were built with an unpinned argbash image.
#
# Usage: scripts/reproduce-release.sh <tag>   (e.g. v1.9.0)
set -euo pipefail

TAG="${1:?Usage: reproduce-release.sh <tag>}"
REPO="${TT_INSTALLER_REPO:-tenstorrent/tt-installer}"

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

echo "[INFO] Cloning ${REPO} at ${TAG}"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "${TAG}" \
	"https://github.com/${REPO}.git" "${workdir}/src"

if [[ ! -x "${workdir}/src/scripts/build-install-sh.sh" ]]; then
	echo "[ERROR] ${TAG} predates scripts/build-install-sh.sh and is not reproducible" >&2
	echo "[ERROR] (older releases were built with an unpinned argbash image)" >&2
	exit 2
fi

echo "[INFO] Rebuilding install.sh from source"
(cd "${workdir}/src" && scripts/build-install-sh.sh "${TAG#v}")
(cd "${workdir}/src" && sha256sum install.sh ttis.sh > SHA256SUMS)

echo "[INFO] Downloading published release assets"
mkdir -p "${workdir}/released"
for asset in install.sh ttis.sh SHA256SUMS; do
	curl -fsSL -o "${workdir}/released/${asset}" \
		"https://github.com/${REPO}/releases/download/${TAG}/${asset}"
done

errors=0
for asset in install.sh ttis.sh SHA256SUMS; do
	rebuilt_sum="$(sha256sum "${workdir}/src/${asset}" | cut -d' ' -f1)"
	released_sum="$(sha256sum "${workdir}/released/${asset}" | cut -d' ' -f1)"
	if [[ "${rebuilt_sum}" == "${released_sum}" ]]; then
		echo "[OK]   ${asset}: rebuilt asset matches release (${released_sum})"
	else
		echo "[FAIL] ${asset}: MISMATCH" >&2
		echo "       rebuilt:  ${rebuilt_sum}" >&2
		echo "       released: ${released_sum}" >&2
		errors=$((errors + 1))
	fi
done

if [[ "${errors}" -gt 0 ]]; then
	echo "[ERROR] ${TAG}: release assets do NOT match a rebuild from the tagged source" >&2
	exit 1
fi
echo "[INFO] ${TAG}: all assets reproduce byte-for-byte from the tagged source"
