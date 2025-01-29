# tt-gimme

> Name WIP.

This script is designed to be downloaded using curl (a la rustup) and be a one-stop-shop for installing the Kernel & User-mode driver, configuring the host system (e.g. enabling hugepages), installing tt-smi and other syseng tools, and installing our SDKs, if desired. It's designed to support two interaction modes:

1. "Just-do-it" mode, which installs a reasonable set of opinionated defaults.
2. Interactive mode, which allows the user to choose what is installed.
    
After running the script, the system should be in the same state as it would be after following our [public docs](https://docs.tenstorrent.com/#software-installation).

## TODO
- Buda/Metalium/NN
