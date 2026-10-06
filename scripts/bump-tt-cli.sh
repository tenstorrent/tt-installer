#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 Tenstorrent AI ULC
# SPDX-License-Identifier: Apache-2.0
#
# bump-tt-cli.sh — update the pinned tt-cli version in install.m4.
#
# tt-cli is the PyPI package "tenstorrent" (it provides the `tt` command). The
# installer installs it as an isolated uv tool pinned to TT_CLI_VERSION, so a
# new tt-cli release reaches users only when this pin moves:
#   1. Resolve the target release (latest on PyPI by default)
#   2. Verify that exact version is published on PyPI with a wheel, so the pin
#      can never point at a yanked or non-existent release
#   3. Cross-check that tenstorrent/tt-cli has a matching GitHub release tag
#      (informational: PyPI is what gets installed)
#   4. Rewrite TT_CLI_VERSION in install.m4
#
# Requirements: curl, jq.
# Usage: scripts/bump-tt-cli.sh [version]   (e.g. 1.0.1; default: latest)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PACKAGE="$(grep -oP '(?<=^readonly TT_CLI_PACKAGE=")[^"]+' install.m4)"
[[ -n "${PACKAGE}" ]] || { echo "[ERROR] TT_CLI_PACKAGE not found in install.m4" >&2; exit 1; }

VERSION="${1:-}"
if [[ -z "${VERSION}" ]]; then
	VERSION="$(curl -fsSL "https://pypi.org/pypi/${PACKAGE}/json" | jq -r '.info.version')"
	echo "[INFO] Latest ${PACKAGE} release on PyPI: ${VERSION}"
fi

release_json="$(curl -fsSL "https://pypi.org/pypi/${PACKAGE}/${VERSION}/json")" \
	|| { echo "[ERROR] No ${PACKAGE} release '${VERSION}' on PyPI" >&2; exit 1; }

if [[ "$(jq -r '.info.yanked // false' <<< "${release_json}")" = "true" ]]; then
	echo "[ERROR] ${PACKAGE} ${VERSION} is yanked on PyPI: $(jq -r '.info.yanked_reason // "no reason given"' <<< "${release_json}")" >&2
	exit 1
fi

wheel="$(jq -r '[.urls[] | select(.packagetype == "bdist_wheel" and (.yanked // false | not))][0] // empty | "\(.filename) sha256=\(.digests.sha256)"' <<< "${release_json}")"
if [[ -z "${wheel}" ]]; then
	echo "[ERROR] ${PACKAGE} ${VERSION} has no (non-yanked) wheel on PyPI; refusing to pin a source-only release" >&2
	exit 1
fi
echo "[INFO] PyPI wheel: ${wheel}"
echo "[INFO] requires-python: $(jq -r '.info.requires_python // "unspecified"' <<< "${release_json}")"

if curl -fsSL -o /dev/null "https://api.github.com/repos/tenstorrent/tt-cli/releases/tags/v${VERSION}"; then
	echo "[INFO] GitHub release v${VERSION} exists: https://github.com/tenstorrent/tt-cli/releases/tag/v${VERSION}"
else
	echo "[WARN] No GitHub release tagged v${VERSION} in tenstorrent/tt-cli (or GitHub unreachable)." >&2
	echo "[WARN] PyPI is what the installer uses, but confirm this is an intended release before committing." >&2
fi

current="$(grep -oP '(?<=^readonly TT_CLI_VERSION=")[^"]+' install.m4)"
if [[ "${current}" = "${VERSION}" ]]; then
	echo "[INFO] install.m4 already pins ${PACKAGE} ${VERSION}; nothing to do."
	exit 0
fi

sed -i -e "s|^readonly TT_CLI_VERSION=.*|readonly TT_CLI_VERSION=\"${VERSION}\"|" install.m4

echo "[INFO] install.m4 updated (${current} -> ${VERSION}):"
grep -n '^readonly TT_CLI_VERSION=' install.m4
echo "[INFO] Review the diff, then commit. CI exercises the pinned install (tt-cli is installed by default)."
