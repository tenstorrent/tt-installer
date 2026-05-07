# Installer State Schema Implementation Plan

## Goal

Create a mechanism to save and load installer state (.ttis files) that captures exact package versions installed, enabling reproducible "golden state" installations.

## Scope

**In scope:** All packages managed by the installer
**Out of scope:** tt-studio, tt-inference-server, tt-metalium containers (git clones / container images)

---

## Current Package Inventory

### 1. Base Packages (installed early, no version tracking)

These are installed directly via hardcoded `apt-get install` / `dnf install` commands around lines 897-919.

| Package | Ubuntu | Debian | Fedora | RHEL/CentOS |
|---------|--------|--------|--------|-------------|
| git | x | x | x | x |
| python3-pip | x | x | x | x |
| python3-devel | | | x | x |
| dkms | x | x | x | x |
| cargo | x | | x | x |
| rustc/rust | x | | x | x |
| pipx | x | x | x | x |
| jq | x | x | x | x |
| protobuf-compiler | x | x | x | x |
| wget | x | x | x | x |
| epel-release | | | | x |

### 2. Container Runtime Packages (lines 797-829)

| Package | apt | dnf |
|---------|-----|-----|
| podman | x | x |
| podman-docker | x | x |
| podman-compose | | x |
| docker (via get.docker.com) | x | x |

### 3. Tenstorrent System Packages (via package_registry, lines 954-966)

| Key | Package Name | Version Arg |
|-----|--------------|-------------|
| kmd | tenstorrent-dkms | `_arg_kmd_version` |
| hugepages | tenstorrent-tools | `_arg_systools_version` |
| sfpi | sfpi | `_arg_sfpi_version` |

### 4. Python Packages (via package_registry, lines 954-966)

| Key | Package Name | Version Arg |
|-----|--------------|-------------|
| tt-topology | tt-topology | `_arg_topology_version` |
| tt-flash | tt-flash | `_arg_flash_version` |
| tt-smi | tt-smi | `_arg_smi_version` |

### 5. Firmware (special handling, lines 1025-1064)

| Item | Version Arg |
|------|-------------|
| fw_pack-*.fwbundle | `_arg_fw_version` |

---

## Proposed Changes

### Phase 1: Distro-Specific Package Flags

Set flags after `detect_distro()` to control which packages are included in the registry:

```bash
set_distro_package_flags() {
    # Defaults - most distros install these
    INSTALL_CARGO="on"
    INSTALL_RUSTC="on"
    INSTALL_PYTHON_DEVEL="off"
    INSTALL_EPEL="off"
    RUST_PKG_NAME="rustc"  # Package name varies by distro

    case "${DISTRO_ID}" in
        "ubuntu")
            # Ubuntu installs cargo and rustc from repos
            ;;
        "debian")
            # Debian's cargo/rustc are too old, user must install separately
            INSTALL_CARGO="off"
            INSTALL_RUSTC="off"
            ;;
        "fedora")
            # Fedora uses "rust" instead of "rustc", needs python3-devel
            RUST_PKG_NAME="rust"
            INSTALL_PYTHON_DEVEL="on"
            ;;
        "rhel"|"centos")
            # RHEL/CentOS need EPEL and python3-devel
            RUST_PKG_NAME="rust"
            INSTALL_EPEL="on"
            INSTALL_PYTHON_DEVEL="on"
            ;;
    esac

    # Container runtime flags (derived from _arg_install_container_runtime)
    INSTALL_PODMAN="off"
    INSTALL_PODMAN_COMPOSE="off"
    if [[ "${_arg_install_container_runtime}" == "podman" ]]; then
        INSTALL_PODMAN="on"
        # podman-compose only on dnf systems (Fedora/RHEL)
        if [[ "${PKG_MANAGER}" == "dnf" ]]; then
            INSTALL_PODMAN_COMPOSE="on"
        fi
    fi
}
```

### Phase 2: Version Query Functions

Add functions to query package versions from package managers:

```bash
# Get version that WOULD be installed (pre-install)
get_candidate_version() {
    local pkg_name="$1"
    case "${PKG_MANAGER}" in
        "apt-get")
            apt-cache policy "${pkg_name}" 2>/dev/null | grep 'Candidate:' | awk '{print $2}'
            ;;
        "dnf")
            dnf repoquery --qf '%{VERSION}-%{RELEASE}' "${pkg_name}" 2>/dev/null | head -1
            ;;
    esac
}

# Get version that IS installed (post-install verification)
get_installed_version() {
    local pkg_name="$1"
    case "${PKG_MANAGER}" in
        "apt-get")
            dpkg-query -W -f='${Version}' "${pkg_name}" 2>/dev/null
            ;;
        "dnf")
            rpm -q --qf '%{VERSION}-%{RELEASE}' "${pkg_name}" 2>/dev/null
            ;;
    esac
}

# Get installed Python package version
get_python_package_version() {
    local pkg_name="$1"
    pip show "${pkg_name}" 2>/dev/null | grep '^Version:' | awk '{print $2}'
}
```

### Phase 3: Unified Package Registry

Refactor to use a single registry for ALL packages, not just TT packages.

```bash
# Package types:
#   base-system  - Base dependencies (git, dkms, etc.)
#   container    - Container runtime packages
#   tt-system    - Tenstorrent system packages from TT repos
#   tt-python    - Tenstorrent Python packages
#
# Format: "package_name|install_flag|version|type"

declare -A package_registry=(
    # Base system packages (always installed)
    ["git"]="git|on||base-system"
    ["python3-pip"]="python3-pip|on||base-system"
    ["dkms"]="dkms|on||base-system"
    ["pipx"]="pipx|on||base-system"
    ["jq"]="jq|on||base-system"
    ["wget"]="wget|on||base-system"
    ["protobuf-compiler"]="protobuf-compiler|on||base-system"
    # Distro-specific (flags set by set_distro_package_flags)
    ["cargo"]="cargo|${INSTALL_CARGO}||base-system"
    ["rustc"]="${RUST_PKG_NAME}|${INSTALL_RUSTC}||base-system"  # rustc on deb, rust on rpm
    ["python3-devel"]="python3-devel|${INSTALL_PYTHON_DEVEL}||base-system"
    ["epel-release"]="epel-release|${INSTALL_EPEL}||base-system"

    # Container runtime (set based on _arg_install_container_runtime)
    ["podman"]="podman|${INSTALL_PODMAN}||container"
    ["podman-docker"]="podman-docker|${INSTALL_PODMAN}||container"
    ["podman-compose"]="podman-compose|${INSTALL_PODMAN_COMPOSE}||container"

    # Tenstorrent system packages
    ["kmd"]="tenstorrent-dkms|${_arg_install_kmd}|${_arg_kmd_version}|tt-system"
    ["hugepages"]="tenstorrent-tools|${_arg_install_hugepages}|${_arg_systools_version}|tt-system"
    ["sfpi"]="sfpi|${_arg_install_sfpi}|${_arg_sfpi_version}|tt-system"

    # Tenstorrent Python packages
    ["tt-topology"]="tt-topology|${_arg_install_tt_topology}|${_arg_topology_version}|tt-python"
    ["tt-flash"]="tt-flash|${_arg_install_tt_flash}|${_arg_flash_version}|tt-python"
    ["tt-smi"]="tt-smi|${_arg_install_tt_smi}|${_arg_smi_version}|tt-python"
)
```

### Phase 4: Version Resolution Function

Resolve empty versions to actual candidate versions before installation:

```bash
resolve_all_versions() {
    log "Resolving package versions..."

    for key in "${!package_registry[@]}"; do
        IFS='|' read -r pkg_name install_flag version pkg_type <<< "${package_registry[${key}]}"

        # Skip disabled packages
        [[ "${install_flag}" != "on" ]] && continue

        # Skip if version already specified
        [[ -n "${version}" ]] && continue

        local resolved=""
        case "${pkg_type}" in
            base-system|container|tt-system)
                resolved=$(get_candidate_version "${pkg_name}")
                ;;
            tt-python)
                # Query PyPI or use pip index versions
                resolved=$(pip index versions "${pkg_name}" 2>/dev/null | grep -oP '\(\K[^)]+' | head -1)
                ;;
        esac

        if [[ -n "${resolved}" ]]; then
            package_registry["${key}"]="${pkg_name}|${install_flag}|${resolved}|${pkg_type}"
            log "  ${pkg_name} -> ${resolved}"
        else
            warn "  ${pkg_name} -> (could not resolve)"
        fi
    done
}
```

### Phase 5: Refactor Installation to Use Registry

Replace hardcoded install commands with registry-driven installation:

```bash
install_packages_by_type() {
    local target_type="$1"
    local -a packages_to_install=()

    for key in "${!package_registry[@]}"; do
        IFS='|' read -r pkg_name install_flag version pkg_type <<< "${package_registry[${key}]}"

        [[ "${install_flag}" != "on" ]] && continue
        [[ "${pkg_type}" != "${target_type}" ]] && continue

        case "${pkg_type}" in
            base-system|container|tt-system)
                if [[ -n "${version}" ]]; then
                    if [[ "${PKG_MANAGER}" = "apt-get" ]]; then
                        packages_to_install+=("${pkg_name}=${version}")
                    else
                        packages_to_install+=("${pkg_name}-${version}")
                    fi
                else
                    packages_to_install+=("${pkg_name}")
                fi
                ;;
            tt-python)
                if [[ -n "${version}" ]]; then
                    packages_to_install+=("${pkg_name}==${version}")
                else
                    packages_to_install+=("${pkg_name}")
                fi
                ;;
        esac
    done

    if [[ ${#packages_to_install[@]} -eq 0 ]]; then
        return 0
    fi

    case "${target_type}" in
        base-system|container|tt-system)
            log "Installing system packages: ${packages_to_install[*]}"
            if [[ "${PKG_MANAGER}" = "apt-get" ]]; then
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages_to_install[@]}"
            else
                sudo dnf install -y "${packages_to_install[@]}"
            fi
            ;;
        tt-python)
            log "Installing Python packages: ${packages_to_install[*]}"
            ${PYTHON_INSTALL_CMD} "${packages_to_install[@]}"
            ;;
    esac
}
```

### Phase 6: State Save/Load Functions

```bash
# .ttis file format (INI-style)
#
# [metadata]
# installer_version=1.0.0
# timestamp=2024-01-15T10:30:00-05:00
# distro=ubuntu
# distro_version=22.04
#
# [base-system]
# git=1:2.34.1-1ubuntu1.10
# dkms=2.8.7-2ubuntu2.2
# ...
#
# [tt-system]
# tenstorrent-dkms=1.29-1
# tenstorrent-tools=1.2.0
# sfpi=0.5.0
#
# [tt-python]
# tt-smi=3.0.0
# tt-flash=2.1.0
# tt-topology=1.0.0
#
# [firmware]
# version=2.4.0

save_installer_state() {
    local output_file="${1:?Output file required}"

    {
        echo "# Tenstorrent Installer State File"
        echo "# DO NOT EDIT MANUALLY"
        echo ""
        echo "[metadata]"
        echo "installer_version=${INSTALLER_VERSION}"
        echo "timestamp=$(date -Iseconds)"
        echo "distro=${DISTRO_ID}"
        echo "distro_version=${VERSION_ID:-unknown}"
        echo ""

        # Group packages by type
        for pkg_type in base-system container tt-system tt-python; do
            echo "[${pkg_type}]"
            for key in "${!package_registry[@]}"; do
                IFS='|' read -r pkg_name install_flag version p_type <<< "${package_registry[${key}]}"
                [[ "${p_type}" != "${pkg_type}" ]] && continue
                [[ "${install_flag}" != "on" ]] && continue
                echo "${pkg_name}=${version}"
            done
            echo ""
        done

        # Firmware version
        echo "[firmware]"
        echo "version=${FW_VERSION:-}"

    } > "${output_file}"

    log "Saved installer state to ${output_file}"
}

load_installer_state() {
    local input_file="${1:?Input file required}"
    local section=""

    if [[ ! -f "${input_file}" ]]; then
        error_exit "State file not found: ${input_file}"
    fi

    log "Loading installer state from ${input_file}"

    # Force non-interactive mode when loading state
    _arg_mode_non_interactive="on"
    set_non_interactive_defaults

    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Trim whitespace
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"

        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue

        # Handle section headers
        if [[ "$key" =~ ^\[.*\]$ ]]; then
            section="${key:1:-1}"
            continue
        fi

        # Map loaded values back to _arg_* variables or registry
        case "${section}" in
            metadata)
                case "$key" in
                    distro)
                        if [[ "${value}" != "${DISTRO_ID}" ]]; then
                            warn "State file was created on ${value}, current system is ${DISTRO_ID}"
                        fi
                        ;;
                esac
                ;;
            tt-system)
                case "$key" in
                    tenstorrent-dkms) _arg_kmd_version="$value"; _arg_install_kmd="on" ;;
                    tenstorrent-tools) _arg_systools_version="$value"; _arg_install_hugepages="on" ;;
                    sfpi) _arg_sfpi_version="$value"; _arg_install_sfpi="on" ;;
                esac
                ;;
            tt-python)
                case "$key" in
                    tt-smi) _arg_smi_version="$value"; _arg_install_tt_smi="on" ;;
                    tt-flash) _arg_flash_version="$value"; _arg_install_tt_flash="on" ;;
                    tt-topology) _arg_topology_version="$value"; _arg_install_tt_topology="on" ;;
                esac
                ;;
            firmware)
                case "$key" in
                    version) _arg_fw_version="$value" ;;
                esac
                ;;
        esac
    done < "${input_file}"
}
```

### Phase 7: New CLI Arguments

Add to argbash definitions:

```bash
# ARG_OPTIONAL_SINGLE([save-state],,[Save installer state to file after installation],[])
# ARG_OPTIONAL_SINGLE([load-state],,[Load installer state from file (implies non-interactive)],[])
```

---

## Refactored main() Flow

```
main()
├── Display logo, version
├── maybe_enable_default_mode()
├── IF --load-state provided:
│   └── load_installer_state(file)  # Sets _arg_* variables, forces non-interactive
├── check_has_sudo_perms()
├── detect_distro()
├── Set distro-specific flags (INSTALL_CARGO, INSTALL_RUSTC, etc.)
├── Build initial package_registry
├── User interactive decisions (if not non-interactive):
│   ├── get_metalium_container_choice()
│   ├── get_inference_server_choice()
│   ├── get_studio_choice()
│   └── get_python_choice()
├── Update package_registry with final decisions
├── resolve_all_versions()  # Fill in empty versions
├── Display installation summary (all packages + versions)
├── install_packages_by_type("base-system")
├── install_tt_repos()
├── install_packages_by_type("container")
├── install_packages_by_type("tt-system")
├── install_packages_by_type("tt-python")
├── Update firmware
├── verify_installed_versions()  # Optional: confirm installed matches expected
├── IF --save-state provided:
│   └── save_installer_state(file)
├── Install non-package items (inference-server, studio, metalium containers)
└── Completion message, reboot prompt
```

---

## Migration Considerations

1. **Backwards compatibility**: Existing CLI args continue to work unchanged
2. **Base packages without versions**: When loading a .ttis file, base-system packages can be treated as "install if missing" rather than requiring exact versions (they're dependencies, not the primary payload)
3. **Version format differences**: apt uses epoch:version-release, dnf uses version-release. State files should store the native format for the distro that created them.
4. **Cross-distro portability**: A .ttis file from Ubuntu won't work on Fedora due to package name and version format differences. Include distro in metadata and warn/error on mismatch.

---

## Testing Checklist

- [ ] `resolve_all_versions()` correctly queries apt-cache on Ubuntu/Debian
- [ ] `resolve_all_versions()` correctly queries dnf on Fedora
- [ ] `save_installer_state()` produces valid .ttis file
- [ ] `load_installer_state()` correctly sets all _arg_* variables
- [ ] Installing with `--load-state` reproduces exact versions
- [ ] Warning displayed when loading state from different distro
- [ ] Empty state file or missing file produces helpful error
