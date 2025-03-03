# tt-installer

This script is designed to be downloaded using curl (a la rustup) and be a one-stop-shop for installing the Kernel & User-mode driver, configuring the host system (e.g. enabling hugepages), installing tt-smi and other syseng tools, and installing our SDKs, if desired. It's designed to support two interaction modes:

1. "Just-do-it" mode, which installs a reasonable set of opinionated defaults.
2. Interactive mode, which allows the user to choose what is installed.
    
After running the script, the system should be in the same state as it would be after following our [public docs](https://docs.tenstorrent.com/#software-installation).

## Usage
(Subject to change, will be usable via Curl once we make repos public)

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
## TODO
