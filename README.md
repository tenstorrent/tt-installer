# tt-installer
Install the tenstorrent software stack with one command.

## Quickstart
```bash
/bin/bash -c "$(curl -fsSL https://github.com/tenstorrent/tt-installer/releases/latest/download/install.sh)"
```
**WARNING:** Take care with this command! Always be careful running unknown code.

## Using tt-metalium
In addition to our system-level tools, this script installs tt-metalium, Tenstorrent's framework for building and running AI models. Metalium is installed as a container using Docker (default) or Podman. You have two container options, both of which can be installed:
- tt-metalium container: 1GB, appropriate for using TT-NN
- tt-metalium Model Demos Container: 10GB, includes a full build of tt-metalium

Using the containers is easy- just run `tt-metalium` or `tt-metalium-models`. By default, this will launch the container with your home directory mounted so you can access your files. You can also run `tt-metalium <command>` to run commands inside the container, such as `tt-metalium "python3"`.

For more about Metalium and TTNN, check out the [examples page](https://docs.tenstorrent.com/tt-metal/latest/ttnn/ttnn/usage.html#basic-examples). For more information about the container, see [this page](https://github.com/tenstorrent/tt-installer/wiki/Using-the-tt%E2%80%90metalium-container) on the wiki.

## Using Python Tools
tt-installer installs two Python tools on your system:
1. tt-smi: Tenstorrent's System Management Interface
2. tt-flash: Utility to update your firmware

Running `tt-smi` launches the interface where you can see your hardware status and confirm the install worked properly.

## Full List of Functions
tt-installer performs the following actions on your system:
1. Installs base packages the software stack depends on
2. Adds Tenstorrent package repositories to your package manager
3. Installs Tenstorrent software from the package repositories, including:
   - Kernel-Mode Driver (KMD)
   - System tools and HugePages configuration
   - Python packages (tt-flash, tt-smi, etc.)
4. Updates your card's firmware using tt-flash
5. Installs a container runtime (Docker by default, Podman optional)
6. Installs tt-metalium as a container and configures the wrapper script for convenient access
7. Installs tt-studio and tt-inference-server, our user-friendly model runtime systems

The installer will ask the user to make choices about Python environments and tt-metalium. If you wish to configure the installation more granularly, see [Advanced Usage](#advanced-usage).

## Advanced Usage
The installer supports command-line arguments for customization. For a full list of available arguments and their environment variable equivalents, please see [this page](https://github.com/tenstorrent/tt-installer/wiki/Customizing-your-installation) on the wiki.

To install from a local file, download the latest install.sh:
```bash
curl -fsSL https://github.com/tenstorrent/tt-installer/releases/latest/download/install.sh -O
chmod +x install.sh
./install.sh
```

To see all available options:
```bash
./install.sh --help
```

To install without prompting the user:
```bash
./install.sh --mode-non-interactive
```

To skip certain components:
```bash
./install.sh --no-install-kmd --no-install-hugepages
```

To use Podman instead of Docker:
```bash
./install.sh --install-container-runtime=podman
```

To skip container runtime installation:
```bash
./install.sh --install-container-runtime=no
```
If you have already installed Docker or Podman, this option will leave them untouched.

To specify versions:
```bash
./install.sh --kmd-version=1.34 --fw-version=18.3.0
```

### Python versioning

By default, we install your distro's python3. If you want to specify a different Python version (e.g. 3.10 on Fedora 43), you can use [uv](https://github.com/astral-sh/uv) and specify a version like so:
```bash
./install.sh --use-uv --python-version 3.10
```

### Version channels

By default the installer pins component versions to a tested **golden baseline**
that ships with each release. Control this with `--versions`:

```bash
# Default: install the golden baseline pinned to this release
./install.sh --versions=release

# Install the latest available version of every component
./install.sh --versions=rolling

# Reproduce an exact configuration from an exported state file
# (this is a full, non-interactive import — used for CI/automation)
./install.sh --versions=/path/to/state.ttis
```

`--export-schema /path/to/state.ttis` writes the resolved state of an install to
a `.ttis` file. It is a developer/CI feature for capturing a configuration to
replay later and is not needed for a normal install.

Note that the installer requires superuser (sudo) permisssions to install packages, add DKMS modules, and configure hugepages.

## Using in CI

tt-installer ships a composite GitHub Action that installs the stack at a
verified-working version set in one step. Pin the `release` channel to get a
known-good baseline, then run your own steps against it. This is handy for two
things:

- **Release gating** — install the verified baseline and run smoke tests to
  confirm a single-package bump didn't break the customer experience.
- **Dev bisection** — install the verified baseline, upgrade *one* package, run
  your tests. If they break, the upgrade is the cause.

Pin the action to a released installer version (the action runs the `install.sh`
from that same release, so the action and installer stay in lockstep). Pick a
version from the [releases page](https://github.com/tenstorrent/tt-installer/releases)
or the Marketplace listing — the examples below use `v3.2.0`.

```yaml
# Dev bisection: known-good baseline, then test your change
- uses: tenstorrent/tt-installer@v3.2.0
  with:
    channel: release          # verified-working version set
- run: pip install --upgrade my-tt-package==1.2.3   # the change under test
- run: pytest tests/          # if this breaks, it's your package
```

The action works on a runner with a Tenstorrent card (full install, the default)
or on a hardware-less runner via `mode: container`, which skips the parts that
need a device (KMD, HugePages, SFPI, container runtime):

```yaml
- uses: tenstorrent/tt-installer@v3.2.0
  with:
    channel: release
    mode: container           # runs on a plain ubuntu runner, no TT card
```

The runner must allow passwordless `sudo` (the installer adds DKMS modules and
configures HugePages). Firmware updates are **off by default** so CI never
flashes a device.

### Action inputs

| Input | Default | Description |
| ----- | ------- | ----------- |
| `channel` | `release` | `--versions`: `release` (golden baseline), `rolling` (latest of everything), or a path to a `.ttis` file. |
| `mode` | `hardware` | `hardware` (full install) or `container` (adds `--mode-container`). |
| `update-firmware` | `off` | `--update-firmware`: `on`, `off`, or `force`. |
| `container-runtime` | `docker` | `--install-container-runtime`: `docker`, `podman`, or `no`. Ignored when `mode: container`. |
| `installer-version` | _(auto)_ | tt-installer release to fetch `install.sh` from. Defaults to the ref the action was called at (e.g. a `vX` tag), falling back to `latest`. |
| `export-schema-path` | `${{ runner.temp }}/tt-installer-state.ttis` | Where the resulting `.ttis` state file is written. |
| `extra-args` | _(empty)_ | Extra arguments appended verbatim, e.g. `--no-install-tt-topology`. |
| `github-token` | `${{ github.token }}` | Passed to `--github-token` to avoid API rate limits. |
| `upload-artifact` | `true` | Upload the exported `.ttis` as a workflow artifact. |

### Action outputs

| Output | Description |
| ------ | ----------- |
| `schema-path` | Absolute path to the exported `.ttis` state file. |
| `installer-version` | The tt-installer release `install.sh` was sourced from. |
| `channel` | The version channel that was used. |

## Distro Compatibility
Our preferred OS is Ubuntu 22.04.5 LTS (Jammy Jellyfish). Other operating systems will not be prioritized for support or features.
For more information, please see this compatibility matrix:
| OS     | Version     | Working? | Notes                                     |
| ------ | ----------- | -------- | ----------------------------------------- |
| Ubuntu | 24.04.2 LTS | Yes      | None                                      |
| Ubuntu | 22.04.5 LTS | Yes      | None                                      |
| Ubuntu | 20.04.6 LTS | No       | Deprecated                                |
| Debian | 13.3        | Yes      | Curl is not installed by default          |
| Fedora | 43          | Yes      | May require restart after base package install |
| Fedora | 42          | Yes      | May require restart after base package install |
| Other DEB-based distros  | N/A          | N/A     | Unsupported but may work |
| Other RPM-based distros  | N/A          | N/A     | Unsupported but may work |
| Arch Linux | N/A     | No       | Unsupported  |
| NixOS      | N/A     | No       | Unsupported, but some TT software is in nixpkgs (unofficial, use at own risk) |
