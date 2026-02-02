# tt-installer
Install the tenstorrent software stack with one command.

## Quickstart
```bash
/bin/bash -c "$(curl -fsSL https://github.com/tenstorrent/tt-installer/releases/latest/download/install.sh)"
```
**WARNING:** Take care with this command! Always be careful running unknown code.

## Using tt-metalium
In addition to our system-level tools, this script installs tt-metalium, Tenstorrent's framework for building and running AI models. Metalium is installed as a container using Podman (default) or Docker. You have two container options, both of which can be installed:
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
5. Installs a container runtime (Podman by default, Docker optional)
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

To use Docker instead of Podman:
```bash
./install.sh --install-container-runtime=docker
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

Note that the installer requires superuser (sudo) permisssions to install packages, add DKMS modules, and configure hugepages.

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
