#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 Tenstorrent AI ULC
# SPDX-License-Identifier: Apache-2.0
#
# ttis.sh — Tenstorrent Installer State manager
#
# Handles .ttis (JSON) file validation, export, and import.
# Designed to run standalone or be sourced by install.sh.
#
# Standalone usage:
#   ttis.sh validate <file>
#
# When sourced by install.sh, also provides:
#   ttis_export  <file> [--force]    — call after install + ttis_resolve_versions
#   ttis_import  <file>              — call before package_registry is built
#   ttis_resolve_versions            — call after install, before ttis_export

# Guard against re-sourcing
[[ -n "${_TTIS_LOADED:-}" ]] && return 0
readonly _TTIS_LOADED=1

set -euo pipefail

# ── Schema version ─────────────────────────────────────────────────────────────
readonly TTIS_SCHEMA_VERSION=1
readonly -a TTIS_VALID_RUNTIMES=(podman docker none)

# ── Core package map ───────────────────────────────────────────────────────────
# Single source of truth for all tracked packages.
# Format per entry: "pkg_name|pkg_type|install_var|version_var"
#   pkg_name:    actual package name used by apt/dnf/pip (also the JSON key)
#   pkg_type:    system (apt/dnf) | python (pip/pipx)
#   install_var: installer _arg_install_* variable name
#   version_var: installer _arg_*_version variable name
#
# All core packages must be present in every .ttis file ("" = not installed).
# Unknown keys in tt_system / tt_python are allowed without validation errors —
# that is the extension point for additional packages without schema bumps.
#
# To add a package: append one line here.
readonly -a TTIS_PACKAGE_MAP=(
	"tenstorrent-dkms|system|_arg_install_kmd|_arg_kmd_version"
	"tenstorrent-tools|system|_arg_install_hugepages|_arg_systools_version"
	"sfpi|system|_arg_install_sfpi|_arg_sfpi_version"
	"tt-smi|python|_arg_install_tt_smi|_arg_smi_version"
	"tt-flash|python|_arg_install_tt_flash|_arg_flash_version"
)

# Populated by ttis_import with extra (non-core) packages from a .ttis file.
# install.m4 appends these into package_registry after the normal build.
# Format per entry: "pkg_name|install_flag|version|pkg_type"
TTIS_IMPORTED_PACKAGES=()

# ── Internal helpers ───────────────────────────────────────────────────────────

_ttis_log()  { echo "[ttis] $*"; }
_ttis_warn() { echo "[ttis] WARNING: $*" >&2; }
_ttis_err()  { echo "[ttis] ERROR: $*" >&2; }

_ttis_require_jq() {
	if ! command -v jq &>/dev/null; then
		_ttis_err "jq is required but not installed"
		return 1
	fi
}

# Read a single raw scalar from a .ttis (JSON) file.
# Returns the literal string "null" if the key does not exist.
_ttis_read() {
	# _ttis_read <file> <jq-dot-path>
	jq -r "$2" "$1"
}

_ttis_safe_path() {
	local p="${1:?_ttis_safe_path: path required}"
	if [[ "${p}" == *".."* ]]; then
		_ttis_err "unsafe path (contains ..): ${p}"; return 1
	fi
	if [[ "${p}" =~ [^[:print:]] ]]; then
		_ttis_err "unsafe path (non-printable characters): ${p}"; return 1
	fi
}

# Query the installed version of a system package (apt/dnf).
_ttis_pkg_version() {
	local pkg="${1:?}"
	case "${PKG_MANAGER:-}" in
		"apt-get")
			dpkg-query -W -f='${Version}' "${pkg}" 2>/dev/null ;;
		"dnf")
			rpm -q --qf '%{VERSION}-%{RELEASE}' "${pkg}" 2>/dev/null \
				| grep -v 'not installed' || true ;;
	esac
}

# Query the installed version of a Python package (pip / pipx).
_ttis_pip_version() {
	local pkg="${1:?}"
	if [[ "${PYTHON_INSTALL_CMD:-}" == pipx* ]]; then
		pipx runpip "${pkg}" show "${pkg}" 2>/dev/null | awk '/^Version:/{print $2}'
	else
		pip show "${pkg}" 2>/dev/null | awk '/^Version:/{print $2}'
	fi
}

# ── ttis_validate ──────────────────────────────────────────────────────────────
#
# Validate a .ttis file.  Exit codes: 0 valid, 1 invalid, 2 unsupported schema.
#
ttis_validate() {
	local file="${1:?ttis_validate: file path required}"
	local errors=0

	_ttis_require_jq || return 1
	_ttis_safe_path "${file}" || return 1

	if [[ ! -e "${file}" ]]; then _ttis_err "file not found: ${file}"; return 1; fi
	if [[ -L "${file}" ]];    then _ttis_err "symlinks not accepted: ${file}"; return 1; fi
	if [[ ! -f "${file}" ]];  then _ttis_err "not a regular file: ${file}"; return 1; fi

	if ! jq '.' "${file}" >/dev/null 2>&1; then
		_ttis_err "not valid JSON: ${file}"; return 1
	fi

	# ── schema_version ──
	local schema_ver
	schema_ver=$(_ttis_read "${file}" '.meta.schema_version')
	if [[ "${schema_ver}" == "null" || -z "${schema_ver}" ]]; then
		_ttis_err "meta.schema_version is required"; return 1
	fi
	if ! [[ "${schema_ver}" =~ ^[0-9]+$ ]]; then
		_ttis_err "meta.schema_version must be an integer, got: '${schema_ver}'"; return 1
	fi
	if [[ "${schema_ver}" -gt "${TTIS_SCHEMA_VERSION}" ]]; then
		_ttis_err "unsupported schema_version ${schema_ver} (supports up to v${TTIS_SCHEMA_VERSION})"
		return 2
	fi

	# ── required metadata fields ──
	local -a required_meta=(installer_version created_at distro_id distro_version distro_family)
	for field in "${required_meta[@]}"; do
		local val
		val=$(_ttis_read "${file}" ".meta.${field}")
		if [[ "${val}" == "null" || -z "${val}" ]]; then
			_ttis_err "meta.${field} is required"
			errors=$((errors + 1))
		fi
	done

	local distro_family
	distro_family=$(_ttis_read "${file}" '.meta.distro_family')
	if [[ "${distro_family}" != "apt" && "${distro_family}" != "dnf" ]]; then
		_ttis_err "meta.distro_family must be 'apt' or 'dnf', got: '${distro_family}'"
		errors=$((errors + 1))
	fi

	# ── core packages: must be present; non-empty value must start with a digit ──
	for entry in "${TTIS_PACKAGE_MAP[@]}"; do
		IFS='|' read -r pkg_name pkg_type _ _ <<< "${entry}"
		local section="tt_${pkg_type}"
		local val
		val=$(_ttis_read "${file}" ".${section}.\"${pkg_name}\"")
		if [[ "${val}" == "null" ]]; then
			_ttis_err "${section}.${pkg_name} is required (core package)"
			errors=$((errors + 1))
		elif [[ -n "${val}" && ! "${val}" =~ ^[0-9] ]]; then
			_ttis_err "${section}.${pkg_name} version '${val}' must start with a digit"
			errors=$((errors + 1))
		fi
	done

	# ── firmware ──
	local fw_version
	fw_version=$(_ttis_read "${file}" '.firmware.version')
	if [[ "${fw_version}" != "null" && -n "${fw_version}" && ! "${fw_version}" =~ ^[0-9] ]]; then
		_ttis_err "firmware.version '${fw_version}' must start with a digit"
		errors=$((errors + 1))
	fi

	# ── container_runtime ──
	local runtime
	runtime=$(_ttis_read "${file}" '.container_runtime.runtime')
	if [[ "${runtime}" != "null" && -n "${runtime}" ]]; then
		local valid=0
		for r in "${TTIS_VALID_RUNTIMES[@]}"; do
			[[ "${runtime}" == "${r}" ]] && valid=1 && break
		done
		if [[ "${valid}" -eq 0 ]]; then
			_ttis_err "container_runtime.runtime must be one of [${TTIS_VALID_RUNTIMES[*]}], got: '${runtime}'"
			errors=$((errors + 1))
		fi
	fi

	if [[ "${errors}" -gt 0 ]]; then
		_ttis_err "${errors} validation error(s) in ${file}"; return 1
	fi

	_ttis_log "valid (schema v${schema_ver}): ${file}"
}

# ── ttis_resolve_versions ─────────────────────────────────────────────────────
#
# Fill in empty versions in package_registry by querying what is installed.
# Iterates package_registry (must be in scope — call from main() after it is built).
# Updates the registry in-place; ttis_export reads the updated values.
#
ttis_resolve_versions() {
	for key in "${!package_registry[@]}"; do
		IFS='|' read -r pkg_name install_flag version pkg_type <<< "${package_registry[${key}]}"
		[[ "${install_flag}" != "on" || -n "${version}" ]] && continue

		local v
		case "${pkg_type}" in
			system) v=$(_ttis_pkg_version "${pkg_name}") ;;
			python) v=$(_ttis_pip_version "${pkg_name}") ;;
			*)      v="" ;;
		esac

		if [[ -n "${v}" ]]; then
			package_registry["${key}"]="${pkg_name}|${install_flag}|${v}|${pkg_type}"
			_ttis_log "resolved ${pkg_name}: ${v}"
		else
			_ttis_warn "could not resolve installed version for ${pkg_name}"
		fi
	done
}

# ── ttis_export ────────────────────────────────────────────────────────────────
#
# Export state to a .ttis file.  Reads package_registry from scope (call from
# main() after ttis_resolve_versions).  All enabled packages must have versions.
#
# Usage: ttis_export <output_path> [--force]
#
ttis_export() {
	local output_path="${1:?ttis_export: output path required}"
	local force="${2:-}"

	_ttis_require_jq || return 1
	_ttis_safe_path "${output_path}" || return 1

	if [[ -e "${output_path}" && "${force}" != "--force" ]]; then
		_ttis_err "${output_path} already exists — pass --force to overwrite"; return 1
	fi

	# Every enabled package must have a resolved version.
	local -a missing=()
	for key in "${!package_registry[@]}"; do
		IFS='|' read -r pkg_name install_flag version _ <<< "${package_registry[${key}]}"
		if [[ "${install_flag}" == "on" && -z "${version}" ]]; then
			missing+=("${pkg_name}")
		fi
	done
	if [[ "${#missing[@]}" -gt 0 ]]; then
		_ttis_err "cannot export — unresolved versions for: ${missing[*]}"
		_ttis_err "run ttis_resolve_versions first, or pass explicit version arguments"
		return 1
	fi

	local distro_family
	case "${PKG_MANAGER:-}" in
		"apt-get") distro_family="apt" ;;
		"dnf")     distro_family="dnf" ;;
		*)
			_ttis_err "PKG_MANAGER not set or unrecognised: '${PKG_MANAGER:-}'"; return 1 ;;
	esac

	local runtime
	case "${_arg_install_container_runtime:-no}" in
		"podman") runtime="podman" ;;
		"docker") runtime="docker" ;;
		*)        runtime="none"   ;;
	esac

	local tmpfile
	tmpfile=$(mktemp --suffix=.ttis)
	# shellcheck disable=SC2064
	trap "rm -f '${tmpfile}'" RETURN

	# ── Accumulate package sections ──
	local sys_json='{}'
	local py_json='{}'
	for key in "${!package_registry[@]}"; do
		IFS='|' read -r pkg_name install_flag version pkg_type <<< "${package_registry[${key}]}"
		if [[ "${pkg_type}" == "system" ]]; then
			sys_json=$(jq --arg k "${pkg_name}" --arg v "${version}" '. + {($k): $v}' <<< "${sys_json}")
		else
			py_json=$(jq --arg k "${pkg_name}" --arg v "${version}" '. + {($k): $v}' <<< "${py_json}")
		fi
	done

	# ── Write the complete JSON in one pass ──
	jq -n \
		--arg iv "${INSTALLER_VERSION:-unknown}" \
		--arg ca "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		--arg di "${DISTRO_ID:-unknown}" \
		--arg dv "${VERSION_ID:-unknown}" \
		--arg df "${distro_family}" \
		--arg hn "$(hostname)" \
		--arg fw "${FW_VERSION:-}" \
		--arg rt "${runtime}" \
		--argjson sys "${sys_json}" \
		--argjson py "${py_json}" \
		'{
			meta: {
				schema_version: 1,
				installer_version: $iv,
				created_at: $ca,
				distro_id: $di,
				distro_version: $dv,
				distro_family: $df,
				hostname: $hn
			},
			tt_system: $sys,
			tt_python: $py,
			firmware: {version: $fw},
			container_runtime: {runtime: $rt}
		}' > "${tmpfile}"

	if ! ttis_validate "${tmpfile}"; then
		_ttis_err "generated file failed validation — not written to ${output_path}"; return 1
	fi

	mv "${tmpfile}" "${output_path}"
	_ttis_log "state saved to ${output_path}"
}

# ── ttis_import ────────────────────────────────────────────────────────────────
#
# Import a .ttis file: validate, check distro compatibility, set _arg_* variables.
# Iterates TTIS_PACKAGE_MAP (package_registry does not exist yet at call time).
# Must be called in the same shell process (not a subshell).
#
# Usage: ttis_import <file>
#
ttis_import() {
	local file="${1:?ttis_import: file path required}"

	_ttis_require_jq || return 1
	_ttis_safe_path "${file}" || return 1

	if [[ ! -e "${file}" ]]; then _ttis_err "file not found: ${file}"; return 1; fi
	if [[ -L "${file}" ]];   then _ttis_err "symlinks not accepted: ${file}"; return 1; fi

	local rc=0
	ttis_validate "${file}" || rc=$?
	if [[ "${rc}" -ne 0 ]]; then
		_ttis_err "import aborted due to validation failure"; return "${rc}"
	fi

	# ── Distro family check (hard error — version formats differ) ──
	local file_family current_family
	file_family=$(_ttis_read "${file}" '.meta.distro_family')
	case "${PKG_MANAGER:-}" in
		"apt-get") current_family="apt" ;;
		"dnf")     current_family="dnf" ;;
		*)         current_family="unknown" ;;
	esac
	if [[ "${file_family}" != "${current_family}" ]]; then
		_ttis_err "distro family mismatch: file='${file_family}', system='${current_family}'"
		_ttis_err ".ttis files are not portable across distro families"
		return 1
	fi

	# ── Distro ID check (warning only) ──
	local file_distro
	file_distro=$(_ttis_read "${file}" '.meta.distro_id')
	if [[ "${file_distro}" != "${DISTRO_ID:-}" ]]; then
		_ttis_warn "distro mismatch: file='${file_distro}', system='${DISTRO_ID:-unknown}' — proceeding"
	fi

	# ── Step 1: read every package from the file into a local array ──
	# Format per entry: "pkg_name|install_flag|version|pkg_type"
	# install_flag is "on" for non-empty versions, "off" for empty string.
	local -a all_pkgs=()
	local section_type
	for section_type in system python; do
		local section="tt_${section_type}"
		local -a keys=()
		mapfile -t keys < <(
			jq -r ".${section} // {} | keys[]" "${file}" 2>/dev/null || true
		)
		local pkg_name
		for pkg_name in "${keys[@]+"${keys[@]}"}"; do
			local val flag
			val=$(_ttis_read "${file}" ".${section}.\"${pkg_name}\"")
			if [[ -n "${val}" && "${val}" != "null" ]]; then flag="on"; else flag="off"; val=""; fi
			all_pkgs+=("${pkg_name}|${flag}|${val}|${section_type}")
		done
	done

	# ── Step 2: verify all core packages are present ──
	local core_entry
	for core_entry in "${TTIS_PACKAGE_MAP[@]}"; do
		IFS='|' read -r core_pkg core_type _ _ <<< "${core_entry}"
		local found=0 pkg_entry
		for pkg_entry in "${all_pkgs[@]}"; do
			IFS='|' read -r imp_pkg _ _ imp_type <<< "${pkg_entry}"
			if [[ "${imp_pkg}" == "${core_pkg}" && "${imp_type}" == "${core_type}" ]]; then
				found=1; break
			fi
		done
		if [[ "${found}" -eq 0 ]]; then
			_ttis_err "core package missing from file: tt_${core_type}.${core_pkg}"
			return 1
		fi
	done

	# ── Step 3: set _arg_* for core packages; collect extras into TTIS_IMPORTED_PACKAGES ──
	TTIS_IMPORTED_PACKAGES=()
	local pkg_entry
	for pkg_entry in "${all_pkgs[@]}"; do
		IFS='|' read -r pkg_name install_flag version pkg_type <<< "${pkg_entry}"
		local is_core=0
		for core_entry in "${TTIS_PACKAGE_MAP[@]}"; do
			IFS='|' read -r core_pkg core_type install_var version_var <<< "${core_entry}"
			if [[ "${pkg_name}" == "${core_pkg}" && "${pkg_type}" == "${core_type}" ]]; then
				printf -v "${install_var}" '%s' "${install_flag}"
				printf -v "${version_var}" '%s' "${version}"
				is_core=1; break
			fi
		done
		if [[ "${is_core}" -eq 0 && "${install_flag}" == "on" ]]; then
			_ttis_warn "extra package '${pkg_name}' (tt_${pkg_type}): not a core package — will attempt to install version ${version}"
			TTIS_IMPORTED_PACKAGES+=("${pkg_name}|${install_flag}|${version}|${pkg_type}")
		fi
	done

	# ── Firmware and container runtime ──
	local val
	val=$(_ttis_read "${file}" '.firmware.version')
	if [[ "${val}" != "null" ]]; then
		if [[ -n "${val}" ]]; then
			_arg_fw_version="${val}"
		else
			# empty string = firmware update was explicitly off when this schema was exported;
			# preserve that intent so importing does not trigger an unexpected firmware flash
			_arg_update_firmware="off"
		fi
	fi

	val=$(_ttis_read "${file}" '.container_runtime.runtime')
	if [[ "${val}" != "null" && -n "${val}" ]]; then
		case "${val}" in
			"podman") _arg_install_container_runtime="podman" ;;
			"docker") _arg_install_container_runtime="docker" ;;
			"none")   _arg_install_container_runtime="no"     ;;
		esac
	fi

	_arg_mode_non_interactive="on"

	local file_distro_ver schema_ver
	file_distro_ver=$(_ttis_read "${file}" '.meta.distro_version')
	schema_ver=$(_ttis_read "${file}" '.meta.schema_version')
	_ttis_log "loaded: ${file_distro} ${file_distro_ver}, schema v${schema_ver} — non-interactive mode enabled"
}

# ── CLI entry point ────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	case "${1:-}" in
		validate) ttis_validate "${2:?Usage: ttis.sh validate <file>}" ;;
		*) echo "Usage: ttis.sh validate <file>" >&2; exit 1 ;;
	esac
fi
