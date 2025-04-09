# tt-installer

This installer script is a one-stop-shop for installing the Kernel & User-mode driver, configuring your host system (e.g. enabling hugepages) and installing tt-smi and other tools.

After running the installer, the system should be in the same state as it would be after following Tenstorrent's [Quickstart docs](https://docs.tenstorrent.com/#software-installation).

## Quickstart
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tenstorrent/tt-installer/refs/heads/main/install.sh)"
```
**WARNING:** Take care with this command! Always be careful running untrusted code.

## Supported Operating Systems
We support Ubuntu 20+, Debian, Fedora, RHEL, and CentOS. Our preferred OS is Ubuntu 22.

Note that Ubuntu 20 is currently deprecated by Metalium and support will be removed in the future.

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

Note that the installer requires superuser (sudo) permisssions to install packages, add DKMS modules, and configure hugepages.
