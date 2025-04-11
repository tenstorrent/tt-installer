# TT-Metalium Docker Installation

The tt-installer now includes support for installing TT-Metalium via Docker. This document explains what TT-Metalium is, how it's installed, and how to customize its installation.

## What is TT-Metalium?

TT-Metalium is Tenstorrent's software stack for running machine learning workloads on Tenstorrent hardware. The Docker image provides a pre-configured environment with all necessary dependencies, making it easy to get started with Tenstorrent hardware.

## Installation Process

During the installation process, the tt-installer will:

1. Check if Docker is installed on your system
   - If not, install Docker and configure it
   - Add your user to the Docker group for permission management
2. Pull the specified version of the TT-Metalium Docker image
3. Create a convenient wrapper script (`tt-metalium`) in your `~/.local/bin` directory
4. Ensure this directory is in your PATH for easy access

After installation, you can simply run `tt-metalium` to start a TT-Metalium container with all appropriate settings for accessing your Tenstorrent hardware.

## Configuration Options

The following environment variables can be used to customize the TT-Metalium installation:

| Variable | Default | Description |
|----------|---------|-------------|
| `TT_SKIP_INSTALL_METALIUM` | `1` | Set to `0` to skip installing TT-Metalium |
| `TT_METALIUM_VERSION` | Latest available | Specify a particular version of TT-Metalium to install |

### Example Usage

To install using a specific version of TT-Metalium:

```bash
TT_METALIUM_VERSION=1.2.3 ./install.sh
```

To skip the TT-Metalium installation:

```bash
TT_SKIP_INSTALL_METALIUM=0 ./install.sh
```

## Using TT-Metalium After Installation

### Basic Usage

After installation, you can start a TT-Metalium container with:

```bash
tt-metalium
```

This will start an interactive container with access to your Tenstorrent hardware and mount your home directory.

### Custom Version

To use a specific version of TT-Metalium after installation:

```bash
TT_METALIUM_VERSION=specific-version tt-metalium
```

### Running Commands

You can run commands directly in the container:

```bash
tt-metalium python -c "import tt_metal; print(tt_metal.get_device_count())"
```

### Script Access

The wrapper script automatically mounts your home directory, allowing you to access your files from inside the container. Your files are available at the same path inside the container as they are outside.

## TT-Metalium Container Details

The TT-Metalium container is configured with:

- Access to all Tenstorrent devices
- HugePages mount for optimal performance
- Your user ID and group ID to avoid permission issues with file access
- Your home directory mounted for easy access to files
- /tmp mounted for temporary storage
- Working directory set to your home directory
- Appropriate environment variables for seamless integration

