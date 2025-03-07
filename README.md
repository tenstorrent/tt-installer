# tt-installer

This script is designed to be downloaded using curl (akin to rustup) and be a one-stop-shop for installing the Kernel & User-mode driver, configuring the host system (e.g. enabling hugepages) and installing tt-smi and other syseng tools.

After running the script, the system should be in the same state as it would be after following Tenstorrent's [Quickstart docs](https://docs.tenstorrent.com/#software-installation).

## TL;DR:
**WARNING:** doing this is potentially a security issue, you had better really trust us if you do this:
```bash
curl https://raw.githubusercontent.com/tenstorrent/tt-installer/refs/heads/main/install.sh | sudo bash
```
We would generally recommend other ways of doing this, noted below.

## Usage
Note that the installer requires superuser (sudo) permisssions to install packages, add DKMS modules, and configure hugepages. Curl will be the preferred usage method once this repository is public.

Run the following:
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
