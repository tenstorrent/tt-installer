# tt-installer

This installer script is a one-stop-shop for installing the Kernel & User-mode driver, configuring your host system (e.g. enabling hugepages), installing tt-smi and other tools, and setting up TT-Metalium Docker image.

After running the installer, the system should be in the same state as it would be after following Tenstorrent's [Quickstart docs](https://docs.tenstorrent.com/#software-installation).

## Quickstart
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tenstorrent/tt-installer/refs/heads/main/install.sh)"
```
**WARNING:** Take care with this command! Always be careful running untrusted code.

## Advanced Usage
Much of the script's behavior can be configured with environment variables- some examples are shown below. For a full list of configurable parameters, please see [this page](https://github.com/tenstorrent/tt-installer/wiki/Customizing-your-installation-with-environment-variables) on the wiki.

Clone the script and run the following:
```bash
git clone https://github.com/tenstorrent/tt-installer.git
cd tt-installer
./install.sh
```
To install without prompting the user:
```bash
git clone https://github.com/tenstorrent/tt-installer.git
cd tt-installer
TT_NON_INTERACTIVE=0 ./install.sh
```
To install without prompting the user and automatically reboot:
```bash
git clone https://github.com/tenstorrent/tt-installer.git
cd tt-installer
TT_NON_INTERACTIVE=0 TT_AUTO_REBOOT=0 ./install.sh
```

To skip installation of specific components:
```bash
# Skip TT-Metalium installation
TT_SKIP_INSTALL_METALIUM=0 ./install.sh
```

Note that the installer requires superuser (sudo) permisssions to install packages, add DKMS modules, and configure hugepages.

## TT-Metalium Docker Installation

The installer includes support for TT-Metalium Docker image installation, which:

1. Installs Docker if not already installed
2. Pulls the TT-Metalium Docker image
3. Creates a convenient `tt-metalium` wrapper script in ~/.local/bin

After installation, you can run TT-Metalium by simply typing:
```bash
tt-metalium
```

This will start a TT-Metalium container with appropriate settings for your Tenstorrent hardware.

To specify a different version of TT-Metalium:
```bash
TT_METALIUM_VERSION=specific-version tt-metalium
```

## Supported Operating Systems
Our preferred OS is Ubuntu 22.04.5 LTS (Jammy Jellyfish).
For other OSes, please see this compatibility matrix:
| OS     | Version     | Working? | Notes                                     |
| ------ | ----------- | -------- | ----------------------------------------- |
| Ubuntu | 24.04.2 LTS | Yes      | None                                      |
| Ubuntu | 22.04.5 LTS | Yes      | None                                      |
| Ubuntu | 20.04.6 LTS | Yes      | Deprecated; support will be removed in a later release|
| Debian | 12.10.0     | Yes      | - Curl is not installed by default<br>- The packaged rustc version is too old to complete installation, we recommend using [rustup](https://rustup.rs/) to install a more modern version|
| Fedora | 41          | Yes      | May require restart after base package install |
| Fedora | 42          | Yes      | May require restart after base package install |
| Other DEB-based distros  | N/A          | N/A     | Unsupported but may work |
| Other RPM-based distros  | N/A          | N/A     | Unsupported but may work |