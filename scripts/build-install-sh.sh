#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 Tenstorrent AI ULC
# SPDX-License-Identifier: Apache-2.0
#
# build-install-sh.sh — produce the released, self-contained install.sh.
#
# This is the single source of truth for the release build: CI
# (.github/workflows/build-test-installer.yml) and independent verifiers
# (scripts/reproduce-release.sh) both call it, so a release asset can be
# reproduced byte-for-byte from its tagged source.
#
# Steps:
#   1. Stamp <version> into install.m4 (in place, replacing the
#      __INSTALLER_DEVELOPMENT_BUILD__ placeholder)
#   2. Compile install.m4 -> install.sh with argbash, pinned by image digest
#   3. Inline ttis.sh so install.sh is a single file
#
# The build is deterministic: same source tree + same version string ->
# byte-identical install.sh. Keep it that way — no timestamps, no
# environment-dependent output.
#
# Usage: scripts/build-install-sh.sh <version>
set -euo pipefail

VERSION="${1:?Usage: build-install-sh.sh <version>}"

# The argbash build container, pinned by digest. The tag is informational;
# the digest is what Docker enforces. Update both together, deliberately —
# Dependabot does not watch this pin.
readonly ARGBASH_IMAGE="matejak/argbash:2.11.0@sha256:9d4cb031d9d7ea893dd84ac02d596bb32560725d6cd1cc19d8c8933019125148"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Use | as the sed delimiter because / can show up in the version string
sed -i "s|__INSTALLER_DEVELOPMENT_BUILD__|${VERSION}|g" install.m4
echo "[INFO] Stamped install.m4 with version ${VERSION}"

docker run --rm \
	-e PROGRAM=argbash \
	-v "$(pwd):/work" \
	-u "$(id -u):$(id -g)" \
	"${ARGBASH_IMAGE}" \
	install.m4 -o install.sh
echo "[INFO] Compiled install.m4 -> install.sh with ${ARGBASH_IMAGE}"

# The released install.sh must be self-contained so it runs via
# `bash -c "$(curl ... install.sh)"` with no second file to fetch.
scripts/inline-ttis.sh install.sh ttis.sh
