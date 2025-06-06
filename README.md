# tt-installer
Install the tenstorrent software stack with one command.

## Quickstart
```bash
/bin/bash -c "$(curl -fsSL https://github.com/tenstorrent/tt-installer/releases/latest/download/install.sh)"
```
**WARNING:** Take care with this command! Always be careful running untrusted code.

## Using tt-metalium
In addition to our system-level tools, this script installs tt-metalium, Tenstorrent's framework for building and running AI models. Metalium is installed as a container using Podman. Using the container is easy- just run `tt-metalium`. By default, this will launch the container with your home directory mounted so you can access your files. You can also run `tt-metalium <command>` to run commands inside the container, such as `tt-metalium "python3"`.

For more about Metalium and TTNN, check out the [examples page](https://docs.tenstorrent.com/tt-metal/latest/ttnn/ttnn/usage.html#basic-examples). For more information about the container, see [this page](https://github.com/tenstorrent/tt-installer/wiki/Using-the-tt%E2%80%90metalium-container) on the wiki.

## Using Python Tools
tt-installer installs two Python tools on your system:
1. tt-smi: Tenstorrent's System Management Interface
2. tt-flash: Utility to update your firmware

Running `tt-smi` launches the interface where you can see your hardware status and confirm the install worked properly.

## Full List of Functions
tt-installer performs the following actions on your system:
1. Using your package manager, installs base packages the software stack depends on
2. Configures a Python environment to install Python packages
3. Installs tenstorrent's Kernel-Mode Driver (KMD)
4. Installs tt-flash and updates your card's firmware
5. Configures HugePages, which are necessary for fast access to your Tenstorrent hardware
6. Installs tt-smi, our System Management Interface
7. Using your package manager, installs Podman
8. Installs tt-metalium as a Podman container and configures the tt-metalium script for convenient access to it

The installer will ask the user to make choices about Python environments and tt-metalium. If you wish to configure the installation more granuarly, see [Advanced Usage](#advanced-usage).

## Advanced Usage
Much of the installer's behavior can be configured with environment variables- some examples are shown below. For a full list of configurable parameters, please see [this page](https://github.com/tenstorrent/tt-installer/wiki/Customizing-your-installation-with-environment-variables) on the wiki.

To install from a local file, clone this repository and run install.sh:
```bash
git clone https://github.com/tenstorrent/tt-installer.git
cd tt-installer
./install.sh
```
To install without prompting the user:
```bash
git clone https://github.com/tenstorrent/tt-installer.git
cd tt-installer
TT_MODE_NON_INTERACTIVE=0 ./install.sh
```
To install without prompting the user and automatically reboot:
```bash
git clone https://github.com/tenstorrent/tt-installer.git
cd tt-installer
TT_MODE_NON_INTERACTIVE=0 TT_REBOOT_OPTION=3 ./install.sh
```

### All options:
| Option                      | What it does                                  | Example |
| --------------------------- | --------------------------------------------- | ------- |
| TT_MODE_NON_INTERACTIVE=0   | Don't ask the user questions during install   | `TT_MODE_NON_INTERACTIVE=0 ./install.sh` |
| TT_REBOOT_OPTION=[123]      | 1 = Ask the user<br/>2 = never<br/>3 = always | To automatically reboot:<br/>`TT_REBOOT_OPTION=3 ./install.sh` |
| TT_SKIP_INSTALL_KMD=0       | Skip KMD installation flag (set to 0 to skip) | `TT_SKIP_INSTALL_KMD=0 ./install.sh` |
| TT_SKIP_INSTALL_HUGEPAGES=0 | Skip HugePages installation flag (set to 0 to skip) | `TT_SKIP_INSTALL_HUGEPAGES=0 ./install.sh` |
| TT_SKIP_UPDATE_FIRMWARE=0   | Skip tt-flash and firmware update flag (set to 0 to skip) | `TT_SKIP_UPDATE_FIRMWARE=0 ./install.sh` |
| TT_SKIP_INSTALL_PODMAN=0    | Skip Podman installation flag (set to 0 to skip) | `TT_SKIP_INSTALL_PODMAN=0 ./install.sh` |
| TT_SKIP_INSTALL_METALIUM_CONTAINER=0 | Skip Podman Metalium installation flag (set to 0 to skip) | `TT_SKIP_INSTALL_METALIUM_CONTAINER=0 ./install.sh` |
| TT_PYTHON_CHOICE=[1234]     | 1 = Use active venv<br/>2 = Create new venv<br/>3 = system level (not recommended)<br/>4 = Use pipx | Create new virtual environment:<br/>`TT_PYTHON_CHOICE=2 ./install.sh` |
| TT_MODE_CONTAINER=0         | Container mode flag (set to 0 to enable, which skips KMD and HugePages and never reboots) | `TT_MODE_CONTAINER=0 ./install.sh` |
| TT_METALIUM_IMAGE_URL=<url> | Change the container base url used to install metalium (or any other container) | `TT_METALIUM_IMAGE_URL=ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-release-amd64 ./install.sh` |
| TT_METALIUM_IMAGE_TAG=<tag> | Change the container tag | `TT_METALIUM_IMAGE_TAG=latest-rc ./install.sh` |


Note that the installer requires superuser (sudo) permisssions to install packages, add DKMS modules, and configure hugepages.

## Supported Operating Systems
Our preferred OS is Ubuntu 22.04.5 LTS (Jammy Jellyfish). Other operating systems will not be prioritized for support or features.
For more information, please see this compatibility matrix:
| OS     | Version     | Working? | Notes                                     |
| ------ | ----------- | -------- | ----------------------------------------- |
| Ubuntu | 24.04.2 LTS | Yes      | None                                      |
| Ubuntu | 22.04.5 LTS | Yes      | None                                      |
| Ubuntu | 20.04.6 LTS | Yes      | - Deprecated; support will be removed in a later release<br>- Metalium cannot be installed|
| Debian | 12.10.0     | Yes      | - Curl is not installed by default<br>- The packaged rustc version is too old to complete installation, we recommend using [rustup](https://rustup.rs/) to install a more modern version|
| Fedora | 41          | Yes      | May require restart after base package install |
| Fedora | 42          | Yes      | May require restart after base package install |
| Other DEB-based distros  | N/A          | N/A     | Unsupported but may work |
| Other RPM-based distros  | N/A          | N/A     | Unsupported but may work |

